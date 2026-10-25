import Foundation

enum DownloadState: String, Codable {
  case queued
  case paused
  case downloading
  case remuxing
  case ready
  case failed
  case cancelled
}

/// One lesson in the queue, persisted so a download survives a relaunch.
struct DownloadTask: Codable, Identifiable, Hashable {
  let uuid: String
  var title: String
  var kind: String
  var role: String
  var category: String
  var courseTitle: String?
  var durationSec: Int
  var quality: String?
  var actualQuality: String?
  var state: DownloadState
  var segmentsDone: Int
  var segmentsTotal: Int
  var bytes: Int64
  var error: String?
  var createdAt: Date
  var finishedAt: Date?
  var path: String?

  var id: String { uuid }

  var request: DownloadRequest {
    DownloadRequest(
      uuid: uuid,
      title: title,
      kind: kind,
      role: role,
      category: category,
      courseTitle: courseTitle,
      durationSec: durationSec
    )
  }

  var fraction: Double {
    guard segmentsTotal > 0 else { return state == .ready ? 1 : 0 }
    return min(1, Double(segmentsDone) / Double(segmentsTotal))
  }

  var isActive: Bool { state == .downloading || state == .remuxing || state == .queued || state == .paused }
}

/// The on-device download queue.
///
/// One lesson at a time, because the point is to leave the phone responsive
/// while a course comes down; each lesson still fetches four parts at once.
///
/// The parts are fetched by `BackgroundTransfer`, so a lesson keeps arriving
/// while the app is suspended, and the system wakes the app to hand each one
/// over. `wake()` is that path — a relaunch in the background has no scene to
/// start the queue from.
@MainActor
final class DownloadManager: ObservableObject {
  static let shared = DownloadManager()

  @Published private(set) var tasks: [DownloadTask] = []
  @Published private(set) var bytesPerSecond: Double = 0

  /// Called after the library on disk changed, so the sources can rescan.
  var onChange: (@MainActor () -> Void)?

  /// The user's quality fallback order, kept in step with the settings screen.
  var qualityPriority: [String] = QualityPlan.defaultPriority

  private let downloader = SegmentDownloader.shared
  private let storeURL = JSONFile.url("downloads")
  /// Where a finished lesson is written. Changing it only affects downloads
  /// started afterwards — one already running keeps the folder it began in.
  var root: URL {
    didSet { pump() }
  }
  private let scratch: URL
  /// True while the library is moving: no lesson starts, so nothing is written
  /// into a folder that is being carried elsewhere.
  private var held = false
  private var runner: Task<Void, Never>?
  private var running: String?
  private var saveTask: Task<Void, Never>?
  private var sample: (at: Date, bytes: Int64)?

  private let activity = DownloadActivityController()
  /// Ends when this lesson stops running, however it stops.
  private var lease: BackgroundLease?

  init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
    self.root = root
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    scratch = caches.appendingPathComponent("downloads", isDirectory: true)
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

    if let saved = JSONFile.load([DownloadTask].self, from: storeURL) {
      tasks = saved.map { task in
        var task = task
        // A download that was in flight when the app died is not running now.
        if task.state == .downloading || task.state == .remuxing { task.state = .queued }
        return task
      }
    }
    pruneMissing()
  }

  // MARK: - Lookups

  func task(for uuid: String) -> DownloadTask? {
    tasks.first { $0.uuid == uuid }
  }

  func isReady(_ uuid: String) -> Bool {
    guard let task = task(for: uuid) else { return false }
    return task.state == .ready
  }

  var activeCount: Int { tasks.filter(\.isActive).count }
  var readyCount: Int { tasks.filter { $0.state == .ready }.count }
  var readyBytes: Int64 { tasks.filter { $0.state == .ready }.reduce(0) { $0 + $1.bytes } }
  var queue: [DownloadTask] {
    tasks.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
  }
  var finished: [DownloadTask] {
    tasks.filter { $0.state == .ready }.sorted { ($0.finishedAt ?? $0.createdAt) > ($1.finishedAt ?? $1.createdAt) }
  }
  var failed: [DownloadTask] {
    tasks.filter { $0.state == .failed }.sorted { $0.createdAt > $1.createdAt }
  }

  // MARK: - Commands

  /// Add lessons to the queue. A lesson already queued, downloading or on disk is
  /// left alone — enqueueing a whole course twice must not fetch it twice.
  func enqueue(_ requests: [DownloadRequest], quality: String?) {
    var changed = false
    for request in requests {
      if let index = tasks.firstIndex(where: { $0.uuid == request.uuid }) {
        guard tasks[index].state == .failed || tasks[index].state == .cancelled else { continue }
        tasks[index].state = .queued
        tasks[index].error = nil
        tasks[index].quality = quality ?? tasks[index].quality
        tasks[index].segmentsDone = 0
        tasks[index].segmentsTotal = 0
        tasks[index].bytes = 0
      } else {
        tasks.append(DownloadTask(
          uuid: request.uuid,
          title: request.title,
          kind: request.kind,
          role: request.role,
          category: request.category,
          courseTitle: request.courseTitle,
          durationSec: request.durationSec,
          quality: quality,
          actualQuality: nil,
          state: .queued,
          segmentsDone: 0,
          segmentsTotal: 0,
          bytes: 0,
          error: nil,
          createdAt: Date(),
          finishedAt: nil,
          path: nil
        ))
      }
      changed = true
    }
    if changed {
      persist()
      pump()
    }
  }

  func pause(_ uuid: String) {
    if running == uuid {
      runner?.cancel()
      runner = nil
      running = nil
      lease?.end()
      lease = nil
    }
    BackgroundTransfer.shared.cancelLesson(uuid)
    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else { return }
    if tasks[index].state == .downloading || tasks[index].state == .remuxing || tasks[index].state == .queued {
      tasks[index].state = .paused
    }
    persist()
    pump()
  }

  func resume(_ uuid: String) {
    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else { return }
    guard tasks[index].state == .paused || tasks[index].state == .failed else { return }
    tasks[index].state = .queued
    tasks[index].error = nil
    persist()
    pump()
  }

  func cancel(_ uuid: String) {
    if running == uuid {
      runner?.cancel()
      runner = nil
      running = nil
      lease?.end()
      lease = nil
    }
    BackgroundTransfer.shared.cancelLesson(uuid)
    tasks.removeAll { $0.uuid == uuid }
    try? FileManager.default.removeItem(at: scratch.appendingPathComponent(uuid, isDirectory: true))
    persist()
    pump()
  }

  func retry(_ uuid: String) {
    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else { return }
    tasks[index].state = .queued
    tasks[index].error = nil
    tasks[index].segmentsDone = 0
    tasks[index].segmentsTotal = 0
    tasks[index].bytes = 0
    persist()
    pump()
  }

  /// Forget a finished row without touching the file on disk.
  func forget(_ uuid: String) {
    tasks.removeAll { $0.uuid == uuid }
    persist()
  }

  func removeFile(_ uuid: String) {
    if let path = task(for: uuid)?.path {
      try? FileManager.default.removeItem(atPath: path)
    }
    tasks.removeAll { $0.uuid == uuid }
    persist()
    onChange?()
  }

  func clearFinished() {
    tasks.removeAll { $0.state == .ready }
    persist()
  }

  // MARK: - Running

  /// Stop starting lessons and wait for the one being written, so the library can
  /// be moved without a half-written file being carried off or left behind.
  func hold() async {
    held = true
    while running != nil {
      try? await Task.sleep(for: .milliseconds(200))
    }
  }

  func release() {
    held = false
    pump()
  }

  /// Follow the files a moved library took with it: a finished lesson remembers
  /// its absolute path, which the move just rewrote. A file the move left behind
  /// keeps its old path, because that is still where it is.
  func relocate(from source: URL, to destination: URL) {
    var changed = false
    for index in tasks.indices {
      guard tasks[index].state == .ready, let path = tasks[index].path else { continue }
      guard let moved = LibraryMigration.relocated(path, from: source, to: destination),
            FileManager.default.fileExists(atPath: moved)
      else { continue }
      tasks[index].path = moved
      changed = true
    }
    if changed { persist() }
  }

  private func pump() {
    guard !held else { return }
    guard runner == nil else { return }
    guard let next = tasks
      .filter({ $0.state == .queued })
      .sorted(by: { $0.createdAt < $1.createdAt })
      .first
    else { return }

    let uuid = next.uuid
    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else { return }
    tasks[index].state = .downloading
    running = uuid
    sample = nil
    persist()

    let priority = qualityPriority
    let request = next.request
    let requested = next.quality

    runner = Task { [weak self] in
      guard let self else { return }
      let downloader = self.downloader
      let scratch = self.scratch
      let root = self.root
      do {
        let outcome = try await downloader.download(
          request: request,
          requestedQuality: requested,
          priority: priority,
          scratchRoot: scratch,
          destinationRoot: root,
          onProgress: { [weak self] progress in
            Task { @MainActor [weak self] in
              self?.apply(progress, to: uuid)
            }
          }
        )
        self.finish(uuid, outcome: outcome)
      } catch DownloadError.cancelled {
        self.interrupt(uuid, reason: nil)
      } catch is CancellationError {
        self.interrupt(uuid, reason: nil)
      } catch let error as DownloadError {
        self.interrupt(uuid, reason: error.errorDescription)
      } catch {
        self.interrupt(uuid, reason: error.localizedDescription)
      }
    }
  }

  /// The system woke the app because a background transfer finished: the part is
  /// already on disk, so the lock screen is told the queue moved on.
  ///
  /// Nothing is started from here on purpose. A relaunch in the background has no
  /// scene, so the library folder the queue writes into has not been resolved yet
  /// — beginning a lesson would put it in the app's own Documents instead of where
  /// the user keeps the library. The queue starts itself the next time the app is
  /// opened; the parts already fetched are skipped.
  func wake() {
    refreshActivity()
  }

  /// Merging the parts and moving the lesson into the library is ordinary work in
  /// this process, unlike the transfers, which the system owns. It is also the one
  /// moment a lesson can freeze half-done: once the last part has landed there are
  /// no more session events to wake the app for, so the merge needs a lease of its
  /// own, taken when it starts rather than with the whole lesson.
  private func holdOpenForMerge() {
    guard lease == nil else { return }
    lease = BackgroundLease("merge")
  }

  /// The lock screen follows the queue, not the other way round: it is redrawn
  /// from the tasks whenever they change, and ends when nothing is left.
  private func refreshActivity() {
    if let summary = QueueSummary.of(tasks) {
      activity.show(summary)
    } else {
      activity.finish()
    }
  }

  private func apply(_ progress: DownloadProgress, to uuid: String) {
    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else { return }
    guard tasks[index].state == .downloading || tasks[index].state == .remuxing else { return }
    tasks[index].segmentsDone = progress.segmentsDone
    tasks[index].segmentsTotal = progress.segmentsTotal
    tasks[index].bytes = progress.bytes
    tasks[index].state = progress.phase == .remuxing ? .remuxing : .downloading
    updateSpeed(bytes: progress.bytes)
    if progress.phase == .remuxing { holdOpenForMerge() }
    refreshActivity()
  }

  private func updateSpeed(bytes: Int64) {
    let now = Date()
    guard let sample else {
      self.sample = (now, bytes)
      return
    }
    let elapsed = now.timeIntervalSince(sample.at)
    guard elapsed >= 0.5 else { return }
    let delta = Double(bytes - sample.bytes)
    let instant = delta / elapsed
    bytesPerSecond = bytesPerSecond == 0 ? instant : bytesPerSecond * 0.6 + instant * 0.4
    self.sample = (now, bytes)
  }

  private func finish(_ uuid: String, outcome: DownloadOutcome) {
    // Only the task that still owns the runner may clear it: a pause or cancel
    // can start the next lesson before this one's task has wound down.
    if running == uuid {
      running = nil
      runner = nil
      bytesPerSecond = 0
    }
    lease?.end()
    lease = nil
    if let index = tasks.firstIndex(where: { $0.uuid == uuid }) {
      tasks[index].state = .ready
      tasks[index].actualQuality = outcome.qualityLabel
      tasks[index].segmentsDone = outcome.segments
      tasks[index].segmentsTotal = outcome.segments
      tasks[index].bytes = outcome.bytes
      tasks[index].path = outcome.url.path
      tasks[index].finishedAt = Date()
      tasks[index].error = nil
    }
    persist()
    onChange?()
    pump()
  }

  private func interrupt(_ uuid: String, reason: String?) {
    if running == uuid {
      running = nil
      runner = nil
      bytesPerSecond = 0
    }
    lease?.end()
    lease = nil
    if let index = tasks.firstIndex(where: { $0.uuid == uuid }),
       tasks[index].state != .paused {
      tasks[index].state = reason == nil ? .queued : .failed
      tasks[index].error = reason
    }
    persist()
    pump()
  }

  // MARK: - Persistence

  private func pruneMissing() {
    tasks.removeAll { task in
      guard task.state == .ready else { return false }
      guard let path = task.path else { return true }
      return !FileManager.default.fileExists(atPath: path)
    }
  }

  private func persist() {
    saveTask?.cancel()
    let snapshot = tasks
    let url = storeURL
    refreshActivity()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      JSONFile.save(snapshot, to: url)
    }
  }
}
