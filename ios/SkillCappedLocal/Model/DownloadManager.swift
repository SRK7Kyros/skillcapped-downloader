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

/// Whether a batch that has just landed needs the app kept awake to hand the next
/// one over. Only a lesson still waiting on parts is worth a lease — a queue that
/// is paused, failed or finished has nothing left to start.
enum TransferHandover {
  static func keepsWorking(_ states: [DownloadState]) -> Bool {
    states.contains { $0 == .queued || $0 == .downloading }
  }

  /// Whether a pump that found the queue in this shape has work to do *in this
  /// process* — a lesson already in flight, or one waiting to start. That is the
  /// one condition under which the app is kept awake, because a window of parts
  /// is refilled by code running here; a transfer itself survives suspension.
  static func needsApp(running: Bool, states: [DownloadState]) -> Bool {
    running || keepsWorking(states)
  }
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
  /// Kept on the row so the name stays the one it was queued under even if the
  /// catalogue is refreshed mid-download.
  var number: FileNumber?
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
      durationSec: durationSec,
      number: number
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
/// over. `wake()` is that path: a relaunch in the background has no scene, so it
/// resolves the library from what was saved and starts the next lesson itself.
@MainActor
final class DownloadManager: ObservableObject {
  static let shared = DownloadManager()

  @Published private(set) var tasks: [DownloadTask] = []
  @Published private(set) var bytesPerSecond: Double = 0
  /// Why the lock-screen card is missing, when it is: the queue is the one place
  /// this can be read without a developer machine.
  @Published private(set) var activityTrouble: String?

  /// Called after the library on disk changed, so the sources can rescan.
  var onChange: (@MainActor () -> Void)?

  /// The user's quality fallback order, kept in step with the settings screen.
  var qualityPriority: [String] = QualityPlan.defaultPriority

  private let downloader = SegmentDownloader.shared
  private let storeURL = JSONFile.url("downloads")
  /// Where a finished lesson is written. Changing it only affects downloads
  /// started afterwards — one already running keeps the folder it began in.
  var root: URL {
    didSet {
      rootIsResolved = true
      pump()
    }
  }
  /// True once a scene — or a background wake — has said where the library is.
  /// Until then `root` is only the app's own folder, which is where a lesson must
  /// not be written when the user keeps the library somewhere else.
  private var rootIsResolved = false
  /// The app's own folder: what `root` starts as, and what a library with nothing
  /// saved resolves to.
  private let ownRoot: URL
  /// A folder resolved with no scene, kept alive for as long as its security scope
  /// is what allows the writes.
  private var adopted: LibraryRoot?
  private let scratch: URL
  /// True while the library is moving: no lesson starts, so nothing is written
  /// into a folder that is being carried elsewhere.
  private var held = false
  private var runner: Task<Void, Never>?
  private var running: String?
  private var saveTask: Task<Void, Never>?
  private var sample: (at: Date, bytes: Int64)?
  /// The attempt allowed to finish the lesson in flight. A lesson restarted for
  /// saying nothing gets a new one, so the task it replaced can never clear the
  /// slot the new attempt holds — which is the reason `finish`/`interrupt` take a
  /// token at all: without it a stale callback from a superseded attempt sets
  /// `runner = nil` while the real one still runs, and the next `pump` starts a
  /// second lesson beside it.
  private var attempt = UUID()
  /// When the lesson in flight last reported anything, how many times it has been
  /// restarted for silence, and which lesson that count belongs to (`LessonStall`).
  private var lastProgressAt: Date?
  private var stallRestarts = 0
  private var stalling: String?
  /// Watches the lesson in flight, so a queue wedged behind it recovers while the
  /// app is open instead of waiting for a relaunch.
  private var ticker: Task<Void, Never>?

  private let activity = DownloadActivityController()
  /// The merge's hold: taken when the last part has landed, because from that
  /// moment there is nothing of the system's left in the air to wake the app for.
  private let mergeHold = BackgroundHold()
  /// Keeps this process running for as long as a lesson is in flight.
  ///
  /// A transfer does not need it — the system owns those and they survive
  /// suspension — but the *refill* does: each window of parts is handed over by
  /// code running here, and iOS suspends an app that holds no assertion and then
  /// delivers the settled parts in batches tens of seconds apart (measured: one
  /// window per 42–114 s, against 88 ms per part while awake). So the hold spans
  /// the lesson rather than its hand-over, and a lesson that outlives the ~30 s a
  /// grant lasts takes the next one at the next part that settles. `renew` asks the
  /// lease whether the system is still honouring it, never whether one exists.
  private let lessonHold = BackgroundHold()
  /// The queue as iOS is told about it while the app is away: the numbers behind
  /// the system's own card, and the total a lesson that has not started is planned
  /// against. Kept across pumps so the bar only ever moves forwards.
  private var continuedRun = ContinuedRun()

  init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
    self.root = root
    ownRoot = root
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

    // The two questions iOS 26 asks of this queue. Both arrive on the main actor:
    // one when its continued-processing task is taken away, one when that task
    // starts or ends and the lock-screen card has to be refreshed either way.
    ContinuedProcessing.shared.onExpire = { [weak self] in
      self?.continuedWasTakenAway()
    }
    ContinuedProcessing.shared.onStateChange = { [weak self] in
      self?.refreshActivity()
    }
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
          number: request.number,
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
      releaseLeases()
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
      releaseLeases()
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
    guard !held else {
      BackgroundJournal.shared.record("pump: held for the library move")
      return
    }
    // Nothing starts until the library is known: `root` begins as the app's own
    // folder, so a queue that ran before the choice was read would write a lesson
    // somewhere the user does not keep the library.
    guard rootIsResolved else {
      BackgroundJournal.shared.record("pump: library not resolved")
      return
    }
    // A row that says it is downloading while nothing is running is what a lost
    // callback leaves behind, and nothing else would look at it again — the queue
    // only ever starts `.queued` rows, so it would sit there for ever and every
    // later pump would find nothing to do. Repairing it here means a wake or a
    // foreground can always make progress, whatever happened before.
    if runner == nil, running == nil {
      let orphans = tasks.indices.filter {
        tasks[$0].state == .downloading || tasks[$0].state == .remuxing
      }
      for index in orphans {
        tasks[index].state = .queued
        BackgroundJournal.shared.record("repair: \(tasks[index].title) was left mid-lesson")
      }
      if !orphans.isEmpty { persist() }
    }
    // Whatever called this — a fresh start, a wake that found a lesson already in
    // flight, or the user leaving the app — the refill loop runs in this process,
    // so the app has to stay awake while there is work to do. On iOS 26 that is
    // asked of the system: the queue becomes a continued-processing task, which
    // keeps the app running and puts its progress on a card of the system's own.
    // Everywhere else, and until that task actually starts, it is the background
    // assertion `holdAwake` takes.
    if TransferHandover.needsApp(running: runner != nil, states: tasks.map(\.state)) {
      refreshContinued()
      holdAwake()
    } else {
      ContinuedProcessing.shared.finish()
    }
    guard runner == nil else { return }
    guard let next = tasks
      .filter({ $0.state == .queued })
      .sorted(by: { $0.createdAt < $1.createdAt })
      .first
    else { return }

    let uuid = next.uuid
    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else { return }

    BackgroundJournal.shared.record("pump: start \(next.title)")

    tasks[index].state = .downloading
    running = uuid
    sample = nil
    let token = UUID()
    attempt = token
    lastProgressAt = Date()
    if stalling != uuid {
      stalling = uuid
      stallRestarts = 0
    }
    persist()
    startTicker()

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
        self.finish(uuid, token: token, outcome: outcome)
      } catch DownloadError.cancelled {
        self.interrupt(uuid, token: token, reason: nil)
      } catch is CancellationError {
        self.interrupt(uuid, token: token, reason: nil)
      } catch let error as DownloadError {
        self.interrupt(uuid, token: token, reason: error.errorDescription)
      } catch {
        self.interrupt(uuid, token: token, reason: error.localizedDescription)
      }
    }
  }

  /// The system woke the app because a background transfer finished: the part is
  /// already on disk, so the queue is moved on. When the app was relaunched purely
  /// to take delivery, the lesson is started again from the folder the store saved,
  /// which is what keeps a course coming down without the app being opened — the
  /// transfers are the system's, so each relaunch can hand over the next batch.
  ///
  /// It is also the path the scene changes take, in both directions: leaving the
  /// foreground is when the assertion for the lesson in flight has to exist, and
  /// coming back is the one moment the queue can be restarted by hand if the system
  /// stopped waking the app for its transfers.
  ///
  /// A saved folder that cannot be reached starts nothing: a lesson must never land
  /// in the app's own folder because a bookmark went stale while the library sits
  /// somewhere else. The store repairs the choice the next time the app is opened.
  func wake() {
    if !rootIsResolved, let saved = LibraryRoot.resolve(documents: ownRoot) {
      adopted?.stop()
      adopted = saved
      root = saved.url
    }
    BackgroundJournal.shared.record("wake: library \(rootIsResolved ? "known" : "unresolved")")
    // Coming back is the moment a user expects a stalled queue to move, and `pump`
    // alone cannot do it: the lesson that went quiet still holds the slot, so the
    // only way out is to stop waiting on it.
    recoverIfStalled()
    pump()
    refreshActivity()
  }

  /// Merging the parts and moving the lesson into the library is ordinary work in
  /// this process, unlike the transfers, which the system owns. It is also the one
  /// moment a lesson can freeze half-done: once the last part has landed there are
  /// no more session events to wake the app for, so the merge takes a lease of its
  /// own — a full grant from the moment it starts — in place of the lesson's.
  private func holdOpenForMerge() {
    guard !mergeHold.isHolding else { return }
    lessonHold.end()
    mergeHold.renew("merge")
  }

  /// Keep this process running while a lesson is in flight, or take a fresh grant
  /// when the previous one has expired and the app is awake again.
  ///
  /// Skipped while the system is already keeping the app here: every
  /// `beginBackgroundTask` spends the app's background budget, and a continued
  /// processing task has taken over that job entirely.
  private func holdAwake() {
    guard !ContinuedProcessing.shared.isCovering else { return }
    lessonHold.renew("lesson")
  }

  /// Both assertions belong to the lesson that just stopped.
  private func releaseLeases() {
    mergeHold.end()
    lessonHold.end()
  }

  /// The lock screen follows the queue, not the other way round: it is redrawn
  /// from the tasks whenever they change, and ends when nothing is left.
  ///
  /// `refreshContinued` runs first: it is what works out the estimate the card
  /// shows, and it is also what asks iOS for the continued-processing task (or
  /// withdraws it once the queue drains).
  private func refreshActivity() {
    refreshContinued()
    if var summary = QueueSummary.of(tasks) {
      summary.timeLeft = summary.paused ? nil : continuedRun.timeLeftPhrase
      activity.show(summary)
    } else {
      activity.finish()
    }
    activityTrouble = activity.trouble
  }

  /// The system's own card (iOS 26), kept in step with what the queue is actually
  /// doing: the lesson in front, what is left of the queue and how long that should
  /// take. It is refreshed from the same place the app's card is, so the two never
  /// disagree, and only while there is work in this process — which is what the
  /// task exists for.
  private func refreshContinued() {
    guard TransferHandover.needsApp(running: running != nil, states: tasks.map(\.state)) else {
      ContinuedProcessing.shared.finish()
      return
    }
    continuedRun.observe(tasks, bytesPerSecond: bytesPerSecond)
    ContinuedProcessing.shared.keepAlive(continuedRun)
  }

  /// iOS took the queue's continued-processing task away: the person cancelled it
  /// on its card, or the system needed the time for something else, and the two
  /// cannot be told apart. Neither stops the queue any more, because the app's own
  /// card is what reports it and the transfers belong to a background session: the
  /// work carries on under the background assertion that was in charge before
  /// iOS 26 — a window of parts per wake instead of a running process, which is
  /// slow, not stalled. The task is asked for again next time this app is
  /// foregrounded.
  private func continuedWasTakenAway() {
    if TransferHandover.needsApp(running: running != nil, states: tasks.map(\.state)) {
      holdAwake()
    }
    refreshActivity()
  }

  /// The Settings readout's button: ask for a card right now, with the queue's own
  /// numbers if there is a queue and a preview otherwise, then report what iOS
  /// said. Asking in the foreground is the only way iOS allows, so a tap is the
  /// one moment a refusal can be observed directly.
  func startActivityNow() {
    activity.show(QueueSummary.of(tasks) ?? .preview)
    activityTrouble = activity.trouble
  }

  func liveActivityReport() -> LiveActivityReport {
    LiveActivityInspector.read(error: activityTrouble)
  }

  /// Every transfer this process started has settled — a lesson's parts are all on
  /// disk — and the merge still has to run in this process. With nothing left in
  /// the air the system has nothing to wake the app for, so this is the second
  /// place the lesson's assertion is taken: a grant that expired over a long
  /// lesson is renewed here, and the merge that follows replaces it with its own.
  func transferWentIdle() {
    guard runner != nil else { return }
    guard TransferHandover.keepsWorking(tasks.map(\.state)) else {
      BackgroundJournal.shared.record("batch idle: nothing left to continue")
      return
    }
    // The system is holding this process open for the queue already; taking an
    // assertion beside it would spend background budget to duplicate it.
    guard !ContinuedProcessing.shared.isCovering else { return }
    guard !lessonHold.isHolding, !mergeHold.isHolding else { return }
    BackgroundJournal.shared.record("batch idle: lease taken")
    holdAwake()
  }

  private func apply(_ progress: DownloadProgress, to uuid: String) {
    // Progress from an attempt this queue has already stopped waiting on (a stall
    // restart, a pause, a cancel) must not write over the row the new attempt owns.
    guard uuid == running else { return }
    guard let index = tasks.firstIndex(where: { $0.uuid == uuid }) else { return }
    guard tasks[index].state == .downloading || tasks[index].state == .remuxing else { return }
    lastProgressAt = Date()
    tasks[index].segmentsDone = progress.segmentsDone
    tasks[index].segmentsTotal = progress.segmentsTotal
    tasks[index].bytes = progress.bytes
    tasks[index].state = progress.phase == .remuxing ? .remuxing : .downloading
    updateSpeed(bytes: progress.bytes)
    if progress.phase == .remuxing {
      holdOpenForMerge()
    } else {
      // A lesson longer than one grant outlives its assertion; a part settling is
      // a moment the app is awake anyway, so that is where the next one is taken.
      holdAwake()
    }
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

  private func finish(_ uuid: String, token: UUID, outcome: DownloadOutcome) {
    guard token == attempt else { return }
    // Only the task that still owns the runner may clear it: a pause or cancel
    // can start the next lesson before this one's task has wound down.
    if running == uuid {
      running = nil
      runner = nil
      bytesPerSecond = 0
    }
    releaseLeases()
    if let index = tasks.firstIndex(where: { $0.uuid == uuid }) {
      tasks[index].state = .ready
      tasks[index].actualQuality = outcome.qualityLabel
      tasks[index].segmentsDone = outcome.segments
      tasks[index].segmentsTotal = outcome.segments
      tasks[index].bytes = outcome.bytes
      tasks[index].path = outcome.url.path
      tasks[index].finishedAt = Date()
      tasks[index].error = nil
      BackgroundJournal.shared.record("done \(tasks[index].title)")
    }
    persist()
    onChange?()
    pump()
  }

  private func interrupt(_ uuid: String, token: UUID, reason: String?) {
    guard token == attempt else { return }
    if running == uuid {
      running = nil
      runner = nil
      bytesPerSecond = 0
    }
    releaseLeases()
    if let index = tasks.firstIndex(where: { $0.uuid == uuid }),
       tasks[index].state != .paused {
      tasks[index].state = reason == nil ? .queued : .failed
      tasks[index].error = reason
      BackgroundJournal.shared.record("stopped \(tasks[index].title): \(reason ?? "cancelled")")
    }
    persist()
    pump()
  }

  // MARK: - A lesson that stops answering

  /// A lesson that has said nothing for `LessonStall.limit` is no longer waited on.
  ///
  /// Called by the ticker while a lesson is in flight and once when the app comes
  /// back, because that is the moment a user expects the queue to move. Nothing
  /// else in the app can rescue this: `pump` refuses to start anything while the
  /// silent lesson's task is alive, and every await that task is sitting on belongs
  /// to code that has already stopped responding.
  private func recoverIfStalled() {
    guard let uuid = running, runner != nil, let since = lastProgressAt else { return }
    let phase = tasks.first { $0.uuid == uuid }?.state
    let limit = phase == .remuxing ? LessonStall.mergeLimit : LessonStall.limit
    guard LessonStall.isStalled(since: since, limit: limit) else { return }
    let title = tasks.first { $0.uuid == uuid }?.title ?? uuid
    let silence = Int(Date().timeIntervalSince(since))
    let restarting = LessonStall.mayRestart(after: stallRestarts)
    BackgroundJournal.shared.record(
      "stall \(title): \(LessonStall.sentence(seconds: silence, restarting: restarting))"
    )
    stopWaiting(on: uuid, silent: silence, givingUp: !restarting)
  }

  /// Drop the lesson in flight without trusting it to wind down: the token is
  /// replaced first, so whatever the abandoned task reports later is ignored, then
  /// its transfers are cancelled before the queue moves on. The parts already on
  /// disk are kept, so a restarted lesson re-fetches only what is missing.
  private func stopWaiting(on uuid: String, silent: Int, givingUp: Bool) {
    attempt = UUID()
    runner?.cancel()
    runner = nil
    running = nil
    sample = nil
    bytesPerSecond = 0
    releaseLeases()
    BackgroundTransfer.shared.cancelLesson(uuid)
    if !givingUp { stallRestarts += 1 }
    if let index = tasks.firstIndex(where: { $0.uuid == uuid }),
       tasks[index].state != .paused {
      if givingUp {
        tasks[index].state = .failed
        tasks[index].error = "Stopped responding — no progress for \(silent) s."
      } else {
        tasks[index].state = .queued
        tasks[index].error = nil
      }
    }
    persist()
    pump()
  }

  /// One timer for the lesson in flight. It asks `recoverIfStalled` every 20 s and
  /// stops itself once nothing is running, so an idle queue costs nothing; a
  /// suspended app runs no timers at all, which is why `wake` checks directly.
  private func startTicker() {
    guard ticker == nil else { return }
    ticker = Task { [weak self] in
      while true {
        do {
          try await Task.sleep(for: .seconds(20))
        } catch {
          return
        }
        guard let self else { return }
        guard self.runner != nil else {
          self.ticker = nil
          return
        }
        self.recoverIfStalled()
      }
    }
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
