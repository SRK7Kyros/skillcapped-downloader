import AVFoundation
import Foundation

/// The player item for a downloaded lesson, plus the loader it depends on.
///
/// The CDN serves MPEG-TS, and iOS's AVFoundation has no demuxer for a bare
/// transport-stream file: `AVURLAsset.loadTracks` answers zero tracks for a real
/// segment (measured in CI, not assumed). MPEG-TS is only playable through the
/// HLS stack, so a `.ts` file is offered to the player as a one-segment playlist
/// whose bytes this loader serves from disk. Nothing is re-encoded and no server
/// runs; any other container is handed to `AVPlayerItem(url:)` untouched.
enum LessonMedia {
  /// The item to play, and the loader that has to outlive it.
  static func item(url: URL, seconds: Int) -> (item: AVPlayerItem, loader: StreamAsset?) {
    guard let media = reader(url: url, seconds: seconds) else {
      return (AVPlayerItem(url: url), nil)
    }
    return (AVPlayerItem(asset: media.asset), media.loader)
  }

  /// The asset to read (a frame, the duration), and the loader to keep alive
  /// until the read finishes.
  static func assets(url: URL, seconds: Int) -> (asset: AVAsset, loader: StreamAsset?)? {
    reader(url: url, seconds: seconds)
  }

  private static func reader(url: URL, seconds: Int) -> (asset: AVAsset, loader: StreamAsset)? {
    guard StreamAsset.handles(url) else { return nil }
    let loader = StreamAsset(file: url, seconds: seconds)
    let asset = AVURLAsset(url: loader.playlistURL)
    asset.resourceLoader.setDelegate(loader, queue: loader.queue)
    return (asset, loader)
  }
}

/// Serves one transport stream as a one-segment HLS playlist.
///
/// The player asks for the playlist, then for byte ranges of `segment.ts`; both
/// are answered from the file on disk. The single `#EXTINF` is the lesson's own
/// duration from the catalogue, which is what the scrubber and "finished"
/// tracking read.
final class StreamAsset: NSObject, AVAssetResourceLoaderDelegate {
  static let scheme = "skcstream"
  /// Bytes handed over per `respond(with:)`. Small enough that a seek is
  /// answered quickly, large enough to keep the demuxer fed.
  static let chunk = 512 * 1024
  /// The playlist has to state a duration. A lesson the catalogue does not know
  /// (a hand-copied file) gets a long one: playback is exact, only the timeline
  /// is a guess until the stream ends.
  static let unknownSeconds = 3600

  /// Serial on purpose: the loader processes requests synchronously on this
  /// queue, so a concurrent one lets two answers interleave and stall it.
  let queue = DispatchQueue(label: "com.kyros.skillcappedlocal.stream")

  private let file: URL
  private let seconds: Int

  init(file: URL, seconds: Int) {
    self.file = file
    self.seconds = seconds
    super.init()
  }

  static func handles(_ url: URL) -> Bool {
    ["ts", "mts", "m2ts"].contains(url.pathExtension.lowercased())
  }

  var playlistURL: URL {
    URL(string: "\(Self.scheme)://lesson/stream.m3u8")!
  }

  var playlist: String {
    let length = Double(seconds > 0 ? seconds : Self.unknownSeconds)
    return """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-TARGETDURATION:\(Int(length.rounded(.up)))
    #EXT-X-MEDIA-SEQUENCE:0
    #EXTINF:\(String(format: "%.3f", length)),
    segment.ts
    #EXT-X-ENDLIST

    """
  }

  // MARK: - Serving

  private let lock = NSLock()
  private var dropped: Set<ObjectIdentifier> = []
  private var log: [String] = []

  /// What the player asked this loader for, newest last. A failing test reads it
  /// to tell "the player never asked" apart from "the player asked and the bytes
  /// it wanted were not there".
  func requests() -> String {
    lock.lock()
    defer { lock.unlock() }
    return log.joined(separator: " | ")
  }

  private func note(_ line: String) {
    lock.lock()
    log.append(line)
    if log.count > 40 {
      log.removeFirst(log.count - 40)
    }
    lock.unlock()
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard let url = loadingRequest.request.url else { return false }
    let ask = loadingRequest.dataRequest
    note(
      "\(url.lastPathComponent) offset=\(ask?.requestedOffset ?? -1) "
        + "length=\(ask?.requestedLength ?? -1) "
        + "all=\(ask?.requestsAllDataToEndOfResource ?? false)"
    )
    if url.pathExtension.lowercased() == "m3u8" {
      let body = Data(playlist.utf8)
      loadingRequest.contentInformationRequest?.contentType = "public.m3u8"
      loadingRequest.contentInformationRequest?.contentLength = Int64(body.count)
      loadingRequest.dataRequest?.respond(with: Self.slice(body, for: loadingRequest))
      loadingRequest.finishLoading()
      return true
    }
    serve(loadingRequest)
    return true
  }

  /// A seek abandons the read in flight; its data has to stop flowing then, or
  /// scrubbing through a lesson would pull the whole file off disk.
  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    lock.lock()
    dropped.insert(ObjectIdentifier(loadingRequest))
    lock.unlock()
  }

  private func wasDropped(_ request: AVAssetResourceLoadingRequest) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return dropped.contains(ObjectIdentifier(request))
  }

  private func forget(_ request: AVAssetResourceLoadingRequest) {
    lock.lock()
    dropped.remove(ObjectIdentifier(request))
    lock.unlock()
  }

  private static func slice(_ body: Data, for request: AVAssetResourceLoadingRequest) -> Data {
    guard let data = request.dataRequest else { return body }
    let offset = max(0, Int(data.requestedOffset))
    let length = data.requestsAllDataToEndOfResource ? body.count - offset : data.requestedLength
    let start = min(max(0, offset), body.count)
    let end = min(body.count, start + max(0, length))
    return body.subdata(in: start..<end)
  }

  private func serve(_ request: AVAssetResourceLoadingRequest) {
    defer { forget(request) }
    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size > 0 else {
      request.finishLoading(with: StreamFailure.noBytes)
      return
    }
    if let info = request.contentInformationRequest {
      info.contentType = "public.mpeg-2-transport-stream"
      info.contentLength = Int64(size)
      info.isByteRangeAccessSupported = true
    }
    guard let data = request.dataRequest else {
      request.finishLoading()
      return
    }
    let offset = max(0, data.requestedOffset)
    let available = Int64(size) - offset
    guard available > 0, let handle = try? FileHandle(forReadingFrom: file) else {
      request.finishLoading(with: StreamFailure.unreadable)
      return
    }
    defer { try? handle.close() }
    guard (try? handle.seek(toOffset: UInt64(offset))) != nil else {
      request.finishLoading(with: StreamFailure.unreadable)
      return
    }
    let length = data.requestsAllDataToEndOfResource
      ? available
      : min(Int64(data.requestedLength), available)
    var remaining = length
    while remaining > 0, !wasDropped(request) {
      let take = Int(min(Int64(Self.chunk), remaining))
      guard let bytes = try? handle.read(upToCount: take), !bytes.isEmpty else { break }
      data.respond(with: bytes)
      remaining -= Int64(bytes.count)
    }
    if !wasDropped(request) {
      note("\(file.lastPathComponent) <- \(length - remaining)/\(length)")
      request.finishLoading()
    }
  }
}

enum StreamFailure: LocalizedError {
  case noBytes
  case unreadable

  var errorDescription: String? {
    switch self {
    case .noBytes: return "the file has no bytes in it"
    case .unreadable: return "the file could not be read"
    }
  }
}
