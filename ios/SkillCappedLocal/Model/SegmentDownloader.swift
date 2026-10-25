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
  case storage

  var errorDescription: String? {
    switch self {
    case .cancelled: return "Cancelled."
    case .qualityUnavailable: return "This lesson is no longer published on the CDN."
    case .noSegments: return "The CDN answered but held no video parts."
    case let .segment(index, status): return "Part \(index) failed (HTTP \(status))."
    case let .emptySegment(index): return "Part \(index) came back empty."
    case .storage: return "Not enough space to save this lesson."
    }
  }
}

/// Downloads one lesson straight from the CDN, without a server.
///
/// Each lesson is a numbered run of 10-second MPEG-TS parts
/// (`HIDDEN<quality>-<#####>.ts`) beside a per-rendition manifest that names the
/// parts belonging to the video, and the parts are merged into one transport
/// stream — which is what gets stored, because iOS plays MPEG-TS through its HLS
/// stack and not at all as a bare file.
actor SegmentDownloader {
  static let shared = SegmentDownloader()

  static let cdnOrigin = "https://d13z5uuzt1wkbz.cloudfront.net"
  static let segmentConcurrency = 4
  /// How many parts one hand-over puts in the system's queue. Wide enough that a
  /// normal lesson leaves in a single turn — the point of the change — and bounded
  /// because the session carries the list until it drains.
  static let partWindow = 64
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

  /// Largest part index that exists — read from the rendition's own manifest,
  /// and probed only when the video publishes none. A duration-derived hint is
  /// just where that probe starts.
  func segmentCount(uuid: String, qualityId: Int, durationSec: Int) async throws -> Int {
    let key = "\(uuid):\(qualityId)"
    if let cached = countCache[key] { return cached }

    if let listing = await publishedListing(uuid: uuid, qualityId: qualityId), listing.count > 0 {
      countCache[key] = listing.count
      return listing.count
    }

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

  /// The rendition's manifest, or `nil` when it has none. A dropped connection is
  /// retried once: falling back to probing after one flaky response is how the
  /// stale parts find their way back in.
  private func publishedListing(uuid: String, qualityId: Int) async -> HlsManifest.Listing? {
    guard let url = HlsManifest.url(uuid: uuid, qualityId: qualityId) else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("SkillCappedLocal/2.0 (iOS)", forHTTPHeaderField: "User-Agent")

    for attempt in 1...2 {
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { return nil }
        return HlsManifest.listing(String(decoding: data, as: UTF8.self))
      } catch {
        if attempt == 2 || Task.isCancelled { return nil }
      }
    }
    return nil
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
      // Announced before the merge rather than after it: the merge is ordinary work
      // in this process, so the queue has to start holding the app open for it now.
      onProgress(DownloadProgress(phase: .remuxing, segmentsDone: total, segmentsTotal: total, bytes: bytes))
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
      extension: "ts"
    )

    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: merged, to: destination)
    } catch {
      throw DownloadError.storage
    }
    Self.discardStaleSiblings(of: destination)
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
  ///
  /// The parts go to the background session **before the first suspension**, and
  /// only then does this wait for any of them. That ordering is the design: a
  /// lesson enqueued four parts at a time needed the app to be woken to enqueue
  /// the next four, and iOS owes an app no such wake-up — the system only promises
  /// a relaunch once *all* of a session's transfers are done — so a suspended app
  /// was left with an empty queue and nothing to wake it. A normal lesson now goes
  /// over in one turn; a very long one is handed over in windows, topped up as
  /// each part settles, which is a moment the app is awake for anyway.
  private func fetchParts(
    uuid: String,
    qualityId: Int,
    total: Int,
    jobDir: URL,
    onProgress: @escaping @Sendable (DownloadProgress) -> Void
  ) async throws -> Int64 {
    var existing: Int64 = 0
    var missing: [Int] = []
    for index in 1...total {
      let path = Self.partURL(jobDir, index)
      if Self.isUsable(path) {
        existing += Self.size(of: path)
      } else {
        missing.append(index)
      }
    }
    var done = total - missing.count
    var bytes = existing

    guard !missing.isEmpty else {
      onProgress(DownloadProgress(phase: .downloading, segmentsDone: done, segmentsTotal: total, bytes: bytes))
      return bytes
    }

    var next = 0
    var outstanding: [(index: Int, task: Int)] = []

    func handOver() throws {
      while outstanding.count < Self.partWindow, next < missing.count {
        let index = missing[next]
        next += 1
        try Task.checkCancellation()
        guard let url = Self.segmentURL(uuid: uuid, qualityId: qualityId, index: index) else {
          throw DownloadError.segment(index: index, status: 0)
        }
        let part = BackgroundSegment(uuid: uuid, jobFolder: jobDir, index: index)
        if let task = BackgroundTransfer.shared.start(url, part: part) {
          outstanding.append((index, task))
        }
      }
    }

    try handOver()
    BackgroundJournal.shared.record("handed over \(next) of \(total) parts")

    // Said after the hand-over, never before it: this event releases the queue's
    // start lease, and a lease released while the lesson was still being handed
    // over is exactly the moment the app could be suspended mid-turn.
    onProgress(DownloadProgress(phase: .downloading, segmentsDone: done, segmentsTotal: total, bytes: bytes))

    while !outstanding.isEmpty {
      let part = outstanding.removeFirst()
      let size = try await partSize(part, uuid: uuid, qualityId: qualityId, jobDir: jobDir)
      done += 1
      bytes += size
      onProgress(DownloadProgress(phase: .downloading, segmentsDone: done, segmentsTotal: total, bytes: bytes))
      try Task.checkCancellation()
      try handOver()
    }
    return bytes
  }

  /// One part already handed over: its size, or a retry. A retry is handed to the
  /// session again from here — the app is awake at this point, because a part
  /// settling is what woke it — so it depends on no lease.
  private func partSize(
    _ part: (index: Int, task: Int),
    uuid: String,
    qualityId: Int,
    jobDir: URL
  ) async throws -> Int64 {
    var identifier = part.task
    var lastStatus = 0
    for attempt in 1...3 {
      do {
        return try await BackgroundTransfer.shared.wait(for: identifier)
      } catch let error as DownloadError {
        switch error {
        case .emptySegment, .cancelled, .qualityUnavailable, .noSegments, .storage:
          throw error
        case let .segment(_, status):
          lastStatus = status
          // 403 past the tail is expected; 403 in the middle is throttling.
          guard status == 403 || status == 408 || status == 429 || status >= 500 else {
            throw error
          }
        }
      } catch is CancellationError {
        throw DownloadError.cancelled
      } catch {
        lastStatus = -1
      }
      guard attempt < 3 else { break }
      try? await Task.sleep(for: .milliseconds(300 * attempt))
      try Task.checkCancellation()
      guard let url = Self.segmentURL(uuid: uuid, qualityId: qualityId, index: part.index),
            let retry = BackgroundTransfer.shared.start(
              url,
              part: BackgroundSegment(uuid: uuid, jobFolder: jobDir, index: part.index)
            )
      else { throw DownloadError.segment(index: part.index, status: lastStatus) }
      identifier = retry
    }
    throw DownloadError.segment(index: part.index, status: lastStatus)
  }

  /// Merged into a scratch name and renamed into place, so a crash mid-merge
  /// can never leave a half-written stream that the next attempt resumes from.
  private func merge(total: Int, jobDir: URL, into merged: URL) throws {
    let scratch = merged.appendingPathExtension("part")
    try? FileManager.default.removeItem(at: scratch)
    FileManager.default.createFile(atPath: scratch.path, contents: nil)
    guard let sink = try? FileHandle(forWritingTo: scratch) else { throw DownloadError.storage }
    var written: Int64 = 0
    do {
      for index in 1...total {
        let part = Self.partURL(jobDir, index)
        guard let handle = try? FileHandle(forReadingFrom: part) else {
          throw DownloadError.segment(index: index, status: 0)
        }
        defer { try? handle.close() }
        while true {
          guard let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty else { break }
          try sink.write(contentsOf: data)
          written += Int64(data.count)
        }
      }
      try sink.synchronize()
    } catch {
      try? sink.close()
      try? FileManager.default.removeItem(at: scratch)
      throw error
    }
    try? sink.close()
    guard written > 0 else {
      try? FileManager.default.removeItem(at: scratch)
      throw DownloadError.noSegments
    }
    try? FileManager.default.removeItem(at: merged)
    try FileManager.default.moveItem(at: scratch, to: merged)
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

  static func size(of url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values?.fileSize ?? 0)
  }

  /// An earlier build wrote an `.mp4` here that iOS could never open. The same
  /// lesson must not be listed twice, so every other extension of that exact
  /// name goes.
  static func discardStaleSiblings(of destination: URL) {
    let folder = destination.deletingLastPathComponent()
    let stem = destination.deletingPathExtension().lastPathComponent
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
    for name in names where name != destination.lastPathComponent {
      guard (name as NSString).deletingPathExtension == stem else { continue }
      try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
  }
}

