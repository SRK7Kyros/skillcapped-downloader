import AVFoundation
import Foundation

/// One lesson to fetch, with everything needed to name where it lands.
struct DownloadRequest: Codable, Hashable {
  let uuid: String
  let title: String
  let kind: String
  let role: String
  let category: String
  let courseTitle: String?
  let durationSec: Int

  var shape: DownloadShape {
    DownloadShape(kind: kind, title: title, role: role, category: category, courseTitle: courseTitle)
  }
}

struct DownloadProgress: Sendable {
  enum Phase: Sendable { case downloading, remuxing }
  let phase: Phase
  let segmentsDone: Int
  let segmentsTotal: Int
  let bytes: Int64
}

struct DownloadOutcome: Sendable {
  let url: URL
  let qualityLabel: String
  let bytes: Int64
  let segments: Int
}

enum DownloadError: LocalizedError {
  case cancelled
  case qualityUnavailable
  case noSegments
  case segment(index: Int, status: Int)
  case emptySegment(index: Int)
  case remux(String)
  case storage

  var errorDescription: String? {
    switch self {
    case .cancelled: return "Cancelled."
    case .qualityUnavailable: return "This lesson is no longer published on the CDN."
    case .noSegments: return "The CDN answered but held no video parts."
    case let .segment(index, status): return "Part \(index) failed (HTTP \(status))."
    case let .emptySegment(index): return "Part \(index) came back empty."
    case let .remux(reason): return "Could not finish the file: \(reason)"
    case .storage: return "Not enough space to save this lesson."
    }
  }
}

/// Downloads one lesson straight from the CDN, without a server.
///
/// There is no upstream playlist: every lesson is a numbered run of 10-second
/// MPEG-TS parts (`HIDDEN<quality>-<#####>.ts`), so the tail is found by probing
/// and the parts are merged into one transport stream before being rewrapped as
/// an MP4.
actor SegmentDownloader {
  static let shared = SegmentDownloader()

  static let cdnOrigin = "https://d13z5uuzt1wkbz.cloudfront.net"
  static let segmentConcurrency = 4
  static let maxSegments = 20_000

  private var qualityCache: [String: [String]] = [:]
  private var countCache: [String: Int] = [:]

  // MARK: - Addresses

  nonisolated static func segmentURL(uuid: String, qualityId: Int, index: Int) -> URL? {
    let padded = String(format: "%05d", index)
    return URL(string: "\(cdnOrigin)/\(uuid)/HIDDEN\(qualityId)-\(padded).ts")
  }

  // MARK: - Availability

  /// The renditions the CDN actually publishes for this lesson, best first.
  func availableQualities(uuid: String) async -> [String] {
    if let cached = qualityCache[uuid] { return cached }
    var found: [String] = []
    for tier in QualityTier.standard.sorted(by: { $0.height > $1.height }) {
      guard let url = Self.segmentURL(uuid: uuid, qualityId: tier.id, index: 1) else { continue }
      if await head(url) { found.append(tier.label) }
    }
    qualityCache[uuid] = found
    return found
  }

  /// Largest part index that exists. A duration-derived hint is only a starting
  /// point: an unknown or stale duration must never produce a truncated file.
  func segmentCount(uuid: String, qualityId: Int, durationSec: Int) async throws -> Int {
    let key = "\(uuid):\(qualityId)"
    if let cached = countCache[key] { return cached }

    func exists(_ index: Int) async -> Bool {
      guard let url = Self.segmentURL(uuid: uuid, qualityId: qualityId, index: index) else { return false }
      return await head(url)
    }

    guard await exists(1) else { throw DownloadError.qualityUnavailable }

    let hint = DownloadPlan.expectedSegments(durationSec: durationSec)
    var lo = 1
    var hi = 0
    var step = max(1, hint)
    while hi == 0 {
      let probe = lo + step
      guard probe <= Self.maxSegments else { hi = Self.maxSegments + 1; break }
      if await exists(probe) {
        lo = probe
        step *= 2
      } else {
        hi = probe
      }
    }
    while hi - lo > 1 {
      let mid = (lo + hi) / 2
      if await exists(mid) { lo = mid } else { hi = mid }
    }
    countCache[key] = lo
    return lo
  }

  // MARK: - Download

  func download(
    request: DownloadRequest,
    requestedQuality: String?,
    priority: [String],
    scratchRoot: URL,
    destinationRoot: URL,
    onProgress: @escaping @Sendable (DownloadProgress) -> Void
  ) async throws -> DownloadOutcome {
    let available = await availableQualities(uuid: request.uuid)
    guard let label = QualityPlan.pick(requested: requestedQuality, priority: priority, available: available),
          let qualityId = QualityTier.id(of: label)
    else { throw DownloadError.qualityUnavailable }

    let total = try await segmentCount(uuid: request.uuid, qualityId: qualityId, durationSec: request.durationSec)

    let jobDir = scratchRoot.appendingPathComponent(request.uuid, isDirectory: true)
    try? FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)
    // Keyed by rendition: a merged stream from an earlier attempt at another
    // quality must never be relabelled as this one.
    let merged = jobDir.appendingPathComponent("merged-\(qualityId).ts", isDirectory: false)

    var bytes: Int64 = 0
    if !Self.isUsable(merged) {
      bytes = try await fetchParts(
        uuid: request.uuid,
        qualityId: qualityId,
        total: total,
        jobDir: jobDir,
        onProgress: onProgress
      )
      try merge(total: total, jobDir: jobDir, into: merged)
      for index in 1...total {
        try? FileManager.default.removeItem(at: Self.partURL(jobDir, index))
      }
    } else {
      bytes = Self.size(of: merged)
      onProgress(DownloadProgress(phase: .downloading, segmentsDone: total, segmentsTotal: total, bytes: bytes))
    }

    onProgress(DownloadProgress(phase: .remuxing, segmentsDone: total, segmentsTotal: total, bytes: bytes))

    let destination = DownloadPlan.destination(
      root: destinationRoot,
      shape: request.shape,
      id: request.uuid,
      qualityLabel: label,
      extension: "mp4"
    )

    // The export runs in the job folder, never in the library: AVFoundation
    // writes through a helper that does not inherit the app's access to a folder
    // the user picked, and a half-written file must not land there either.
    let finished = jobDir.appendingPathComponent("finished-\(qualityId).mp4", isDirectory: false)
    try? FileManager.default.removeItem(at: finished)
    do {
      try await Remuxer.remux(ts: merged, to: finished)
      try await Remuxer.verify(finished, expectedSeconds: request.durationSec)
    } catch {
      try? FileManager.default.removeItem(at: finished)
      throw DownloadError.remux((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: finished, to: destination)
    } catch {
      throw DownloadError.storage
    }
    try? FileManager.default.removeItem(at: jobDir)

    return DownloadOutcome(
      url: destination,
      qualityLabel: label,
      bytes: Self.size(of: destination),
      segments: total
    )
  }

  /// Segments already on disk from an interrupted run are kept, so a retry only
  /// fetches what is missing.
  private func fetchParts(
    uuid: String,
    qualityId: Int,
    total: Int,
    jobDir: URL,
    onProgress: @escaping @Sendable (DownloadProgress) -> Void
  ) async throws -> Int64 {
    var existing: Int64 = 0
    var alreadyDone = 0
    for index in 1...total where Self.isUsable(Self.partURL(jobDir, index)) {
      existing += Self.size(of: Self.partURL(jobDir, index))
      alreadyDone += 1
    }
    var done = alreadyDone
    var bytes = existing
    onProgress(DownloadProgress(phase: .downloading, segmentsDone: done, segmentsTotal: total, bytes: bytes))

    try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
      var next = 1
      var inFlight = 0

      while next <= total, inFlight < Self.segmentConcurrency {
        let index = next
        next += 1
        if Self.isUsable(Self.partURL(jobDir, index)) { continue }
        group.addTask {
          let data = try await self.fetchPart(uuid: uuid, qualityId: qualityId, index: index)
          try data.write(to: Self.partURL(jobDir, index), options: .atomic)
          return (index, Int64(data.count))
        }
        inFlight += 1
      }

      while let (_, size) = try await group.next() {
        inFlight -= 1
        done += 1
        bytes += size
        onProgress(DownloadProgress(phase: .downloading, segmentsDone: done, segmentsTotal: total, bytes: bytes))
        try Task.checkCancellation()
        while next <= total, inFlight < Self.segmentConcurrency {
          let index = next
          next += 1
          if Self.isUsable(Self.partURL(jobDir, index)) { continue }
          group.addTask {
            let data = try await self.fetchPart(uuid: uuid, qualityId: qualityId, index: index)
            try data.write(to: Self.partURL(jobDir, index), options: .atomic)
            return (index, Int64(data.count))
          }
          inFlight += 1
        }
      }
    }
    return bytes
  }

  private func fetchPart(uuid: String, qualityId: Int, index: Int) async throws -> Data {
    guard let url = Self.segmentURL(uuid: uuid, qualityId: qualityId, index: index) else {
      throw DownloadError.segment(index: index, status: 0)
    }
    var lastStatus = 0
    for attempt in 1...3 {
      try Task.checkCancellation()
      var request = URLRequest(url: url)
      request.timeoutInterval = 60
      request.setValue("SkillCappedLocal/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        lastStatus = status
        if (200..<300).contains(status) {
          guard !data.isEmpty else { throw DownloadError.emptySegment(index: index) }
          return data
        }
        // 403 past the tail is expected; 403 in the middle is throttling.
        guard status == 403 || status == 408 || status == 429 || status >= 500 else {
          throw DownloadError.segment(index: index, status: status)
        }
      } catch let error as DownloadError {
        if case .emptySegment = error { throw error }
        lastStatus = lastStatus == 0 ? -1 : lastStatus
      } catch is CancellationError {
        throw DownloadError.cancelled
      } catch {
        lastStatus = -1
      }
      if attempt < 3 {
        try? await Task.sleep(for: .milliseconds(300 * attempt))
      }
    }
    throw DownloadError.segment(index: index, status: lastStatus)
  }

  private func merge(total: Int, jobDir: URL, into merged: URL) throws {
    FileManager.default.createFile(atPath: merged.path, contents: nil)
    guard let sink = try? FileHandle(forWritingTo: merged) else { throw DownloadError.storage }
    defer { try? sink.close() }
    for index in 1...total {
      let part = Self.partURL(jobDir, index)
      guard let handle = try? FileHandle(forReadingFrom: part) else {
        throw DownloadError.segment(index: index, status: 0)
      }
      defer { try? handle.close() }
      while true {
        guard let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty else { break }
        try sink.write(contentsOf: data)
      }
    }
    try sink.synchronize()
  }

  nonisolated static func partURL(_ jobDir: URL, _ index: Int) -> URL {
    jobDir.appendingPathComponent(String(format: "%05d.ts", index), isDirectory: false)
  }

  // MARK: - HTTP

  private func head(_ url: URL) async -> Bool {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 20
    if let (_, response) = try? await URLSession.shared.data(for: request),
       let http = response as? HTTPURLResponse {
      if http.statusCode == 405 || http.statusCode == 501 {
        var ranged = URLRequest(url: url)
        ranged.timeoutInterval = 20
        ranged.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if let (_, probe) = try? await URLSession.shared.data(for: ranged),
           let rangedHTTP = probe as? HTTPURLResponse {
          return (200..<400).contains(rangedHTTP.statusCode)
        }
        return false
      }
      return (200..<400).contains(http.statusCode)
    }
    return false
  }

  private static func isUsable(_ url: URL) -> Bool {
    size(of: url) > 0
  }

  private static func size(of url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values?.fileSize ?? 0)
  }
}

/// Rewraps the merged transport stream as an MP4. The bytes are already a valid
/// video, so this only swaps the container — never re-encodes unless the
/// passthrough refuses the stream.
enum Remuxer {
  enum RemuxFailure: LocalizedError {
    case noSession
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .noSession: return "the system could not open the transport stream"
      case let .failed(reason): return reason
      }
    }
  }

  static func remux(ts: URL, to output: URL) async throws {
    let asset = AVURLAsset(url: ts)
    let hasAudio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).count > 0

    do {
      try await export(asset: asset, preset: AVAssetExportPresetPassthrough, to: output)
      if hasAudio, ((try? await AVURLAsset(url: output).loadTracks(withMediaType: .audio)) ?? []).isEmpty {
        throw RemuxFailure.failed("the pass-through lost the audio track")
      }
    } catch {
      // A cancelled download must stop here: re-encoding takes minutes and the
      // user asked for it to end.
      try Task.checkCancellation()
      try? FileManager.default.removeItem(at: output)
      try await export(asset: asset, preset: AVAssetExportPresetHighestQuality, to: output)
    }
  }

  private static func export(asset: AVURLAsset, preset: String, to output: URL) async throws {
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      throw RemuxFailure.noSession
    }
    try? FileManager.default.removeItem(at: output)
    session.outputURL = output
    session.outputFileType = .mp4
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      session.exportAsynchronously { continuation.resume() }
    }
    switch session.status {
    case .completed:
      return
    case .cancelled:
      throw RemuxFailure.failed("the export was cancelled")
    default:
      // The domain and code are what makes a device report actionable: the
      // sentence alone is AVFoundation's catch-all for -11800.
      let code = session.error.map { error -> String in
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
      } ?? "no code"
      let message = session.error?.localizedDescription ?? "the export failed"
      throw RemuxFailure.failed("\(message) [\(code)]")
    }
  }

  /// A truncated remux is worse than none: the output has to be about as long as
  /// the duration the catalogue claims.
  static func verify(_ url: URL, expectedSeconds: Int) async throws {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    guard (values?.fileSize ?? 0) > 0 else {
      throw RemuxFailure.failed("the finished file was empty")
    }
    guard expectedSeconds > 0 else { return }
    let asset = AVURLAsset(url: url)
    guard let duration = try? await asset.load(.duration) else { return }
    let seconds = CMTimeGetSeconds(duration)
    guard seconds.isFinite, seconds > 0 else { return }
    if seconds < Double(expectedSeconds) - 20 {
      throw RemuxFailure.failed("only \(Int(seconds))s of \(expectedSeconds)s were written")
    }
  }
}
