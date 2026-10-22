import AVFoundation
import Foundation
import Network

/// The player item for a downloaded lesson.
///
/// The CDN serves MPEG-TS, and iOS has no demuxer for a bare transport stream:
/// `AVURLAsset.loadTracks` answers zero tracks for a real segment. MPEG-TS is
/// only playable through the HLS stack, which fetches its own segments, so the
/// file is offered as a one-segment playlist over loopback. Any other container
/// is handed to the player untouched.
enum LessonMedia {
  static func item(url: URL, seconds: Int) async -> AVPlayerItem {
    guard let stream = await stream(url: url, seconds: seconds) else {
      return AVPlayerItem(url: url)
    }
    return AVPlayerItem(url: stream)
  }

  /// The asset to read a frame or a duration out of; nil when the file is not a
  /// transport stream and the caller should open it itself.
  static func assets(url: URL, seconds: Int) async -> AVAsset? {
    guard let stream = await stream(url: url, seconds: seconds) else { return nil }
    return AVURLAsset(url: stream)
  }

  private static func stream(url: URL, seconds: Int) async -> URL? {
    guard LessonServer.offers(url) else { return nil }
    return try? await LessonServer.shared.url(for: url, seconds: seconds)
  }
}

/// Serves downloaded lessons over loopback so the player opens them as HLS.
///
/// A resource loader is not an option: Apple's HLS stack refuses the media bytes
/// a delegate answers with, so a playlist served that way reports its duration
/// and never a frame. An ordinary HTTP stream is the shape it does accept.
final class LessonServer: @unchecked Sendable {
  static let shared = LessonServer()

  /// A lesson the catalogue does not know (a hand-copied file) still states a
  /// duration: playback is exact, only the timeline is a guess until the stream
  /// ends.
  static let unknownSeconds = 3600
  static let chunkSize = 512 * 1024
  static let playlistName = "index.m3u8"
  static let segmentName = "segment.ts"

  private let queue = DispatchQueue(label: "com.kyros.skillcappedlocal.lesson-server")
  private let lock = NSLock()
  private var listener: NWListener?
  private var port: UInt16?
  private var broken = false
  private var lessons: [String: Lesson] = [:]

  private struct Lesson {
    let file: URL
    let seconds: Int
  }

  private enum Body {
    case text(String)
    case file(URL)
  }

  private enum Status {
    case badRequest
    case notFound
    case serverError

    var line: String {
      switch self {
      case .badRequest: return "400 Bad Request"
      case .notFound: return "404 Not Found"
      case .serverError: return "500 Internal Server Error"
      }
    }
  }

  /// The playlist URL for a lesson, once the server is listening.
  func url(for file: URL, seconds: Int) async throws -> URL {
    let port = try await start()
    lock.lock()
    lessons[Self.token(for: file)] = Lesson(file: file, seconds: seconds)
    lock.unlock()
    guard let url = URL(string: "http://127.0.0.1:\(port)/lesson/\(Self.token(for: file))/\(Self.playlistName)") else {
      throw LessonServerFailure.noAddress
    }
    return url
  }

  static func offers(_ url: URL) -> Bool {
    ["ts", "mts", "m2ts"].contains(url.pathExtension.lowercased())
  }

  // MARK: - The playlist

  static func playlist(token: String, port: UInt16, seconds: Int) -> String {
    let length = Double(seconds > 0 ? seconds : unknownSeconds)
    return """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-TARGETDURATION:\(Int(length.rounded(.up)))
    #EXT-X-MEDIA-SEQUENCE:0
    #EXTINF:\(String(format: "%.3f", length)),
    http://127.0.0.1:\(port)/lesson/\(token)/\(segmentName)
    #EXT-X-ENDLIST

    """
  }

  // MARK: - Listening

  private func start() async throws -> UInt16 {
    open()
    for _ in 0..<300 {
      lock.lock()
      let (port, broken) = (self.port, self.broken)
      lock.unlock()
      if let port { return port }
      if broken { throw LessonServerFailure.couldNotListen }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw LessonServerFailure.couldNotListen
  }

  private func open() {
    lock.lock()
    defer { lock.unlock() }
    guard listener == nil, !broken else { return }
    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      // Loopback only: the library must never be reachable from the network.
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
      let listener = try NWListener(using: parameters)
      listener.stateUpdateHandler = { [weak self, weak listener] state in
        guard let self else { return }
        lock.lock()
        switch state {
        case .ready: self.port = listener?.port?.rawValue
        case .failed, .cancelled: self.broken = true
        default: break
        }
        lock.unlock()
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      listener.start(queue: queue)
      self.listener = listener
    } catch {
      broken = true
    }
  }

  // MARK: - Serving

  private func accept(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(connection, buffered: Data())
  }

  private func receive(_ connection: NWConnection, buffered: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
      guard let self else { return connection.cancel() }
      var buffer = buffered
      if let data { buffer.append(data) }
      if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
        respond(connection, to: String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self))
      } else if isComplete || error != nil || buffer.count > 32 * 1024 {
        connection.cancel()
      } else {
        receive(connection, buffered: buffer)
      }
    }
  }

  private func respond(_ connection: NWConnection, to requestText: String) {
    let lines = requestText.components(separatedBy: "\r\n")
    let request = (lines.first ?? "").split(separator: " ")
    guard request.count >= 2 else { return fail(connection, .badRequest) }
    let method = String(request[0])
    let path = String(request[1]).split(separator: "?").first.map(String.init) ?? "/"
    let range = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }.flatMap(Self.parseRange)
    guard let (type, body) = resource(for: path) else { return fail(connection, .notFound) }

    switch body {
    case .text(let text):
      let data = method == "HEAD" ? Data() : Data(text.utf8)
      let head = Self.head(
        status: "200 OK",
        type: type,
        length: data.count,
        extra: ["Accept-Ranges: bytes"]
      )
      reply(connection, head: head, body: data)
    case .file(let url):
      serve(connection, file: url, type: type, method: method, range: range)
    }
  }

  private func resource(for path: String) -> (String, Body)? {
    let parts = path.split(separator: "/").map(String.init)
    guard parts.count == 3, parts[0] == "lesson" else { return nil }
    lock.lock()
    let lesson = lessons[parts[1]]
    let port = self.port ?? 0
    lock.unlock()
    guard let lesson else { return nil }
    if parts[2] == Self.playlistName {
      return ("application/vnd.apple.mpegurl", .text(Self.playlist(token: parts[1], port: port, seconds: lesson.seconds)))
    }
    if parts[2] == Self.segmentName {
      return ("video/mp2t", .file(lesson.file))
    }
    return nil
  }

  private func serve(
    _ connection: NWConnection,
    file url: URL,
    type: String,
    method: String,
    range: (Int, Int?)?
  ) {
    guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 else {
      return fail(connection, .notFound)
    }
    var start = 0
    var end = size - 1
    var status = "200 OK"
    var extra = ["Accept-Ranges: bytes"]
    if let (asked, last) = range {
      guard asked < size else {
        let head = Self.head(
          status: "416 Range Not Satisfiable",
          type: type,
          length: 0,
          extra: ["Content-Range: bytes */\(size)"]
        )
        return reply(connection, head: head)
      }
      start = max(0, asked)
      end = min(last ?? (size - 1), size - 1)
      status = "206 Partial Content"
      extra.append("Content-Range: bytes \(start)-\(end)/\(size)")
    }
    let length = end - start + 1
    let head = Self.head(status: status, type: type, length: length, extra: extra)
    guard method != "HEAD" else {
      return reply(connection, head: head)
    }
    guard let handle = try? FileHandle(forReadingFrom: url), (try? handle.seek(toOffset: UInt64(start))) != nil else {
      return fail(connection, .serverError)
    }
    replyHead(connection, head: head) { [weak self] in
      self?.chunk(connection, handle: handle, remaining: length)
    }
  }

  private func chunk(_ connection: NWConnection, handle: FileHandle, remaining: Int) {
    guard remaining > 0 else {
      try? handle.close()
      return finish(connection)
    }
    guard let bytes = try? handle.read(upToCount: min(remaining, Self.chunkSize)), !bytes.isEmpty else {
      try? handle.close()
      return connection.cancel()
    }
    connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
      guard error == nil else {
        try? handle.close()
        return connection.cancel()
      }
      self?.chunk(connection, handle: handle, remaining: remaining - bytes.count)
    })
  }

  private func fail(_ connection: NWConnection, _ status: Status) {
    let head = Self.head(status: status.line, type: "text/plain", length: 0, extra: [])
    reply(connection, head: head)
  }

  // MARK: - Writing

  private static func head(status: String, type: String, length: Int, extra: [String]) -> String {
    (["HTTP/1.1 \(status)", "Content-Type: \(type)", "Content-Length: \(length)"]
      + extra
      + ["Connection: close", "", ""]).joined(separator: "\r\n")
  }

  /// Send the head (with an optional small body), then a graceful end of stream:
  /// a cancel while bytes are still in flight truncates the response.
  private func reply(_ connection: NWConnection, head: String, body: Data = Data()) {
    connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
      guard error == nil, let self else { return connection.cancel() }
      guard !body.isEmpty else { return self.finish(connection) }
      connection.send(content: body, completion: .contentProcessed { [weak self] error in
        guard error == nil, let self else { return connection.cancel() }
        self.finish(connection)
      })
    })
  }

  private func replyHead(_ connection: NWConnection, head: String, then next: @escaping () -> Void) {
    connection.send(content: Data(head.utf8), completion: .contentProcessed { error in
      guard error == nil else { return connection.cancel() }
      next()
    })
  }

  private func finish(_ connection: NWConnection) {
    connection.send(
      content: nil,
      contentContext: .finalMessage,
      isComplete: true,
      completion: .contentProcessed { _ in connection.cancel() }
    )
  }

  private static func parseRange(_ header: String) -> (Int, Int?)? {
    let value = header.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
    guard value.lowercased().hasPrefix("bytes=") else { return nil }
    let spec = value.dropFirst("bytes=".count).split(separator: ",").first.map(String.init) ?? ""
    let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
    guard bounds.count == 2, let start = Int(bounds[0]) else { return nil }
    return (start, bounds[1].isEmpty ? nil : Int(bounds[1]))
  }

  /// FNV-1a over the path: stable for the life of the library, so the same
  /// lesson keeps one URL instead of leaking a route per playback.
  private static func token(for file: URL) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in file.standardizedFileURL.path.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    return String(hash, radix: 16)
  }
}

enum LessonServerFailure: LocalizedError {
  case noAddress
  case couldNotListen

  var errorDescription: String? {
    switch self {
    case .noAddress: return "the lesson stream has no address"
    case .couldNotListen: return "the lesson server could not open a port"
    }
  }
}
