import BackgroundTasks
import Foundation
import UIKit

/// What the queue tells iOS while it asks to keep running after the app is
/// backgrounded, and how far along it is.
///
/// Pure — no UIKit, no system — because the awkward part is arithmetic: a lesson's
/// part count is only known once its manifest has been read, which happens after
/// it starts. Until then its share of the bar is planned from its length at the
/// rate this catalogue publishes parts (measured: 13 parts for a 122.8 s lesson, so
/// ~9 s of footage each), and a plan is fixed the first time a lesson is seen, so a
/// bar that is already moving can never have its total changed underneath it.
struct ContinuedRun {
  /// Seconds of footage one part carries, used only to size a lesson that has not
  /// started yet. A real count from the manifest always wins over this.
  static let secondsPerPart: Double = 9

  private(set) var planned: [String: Int64] = [:]
  private(set) var done: [String: Int64] = [:]
  /// Lessons that landed while this run was watching. Their whole plan counts as
  /// fetched, so finishing one advances the bar instead of taking it back.
  private(set) var landed: Set<String> = []
  private(set) var currentTitle = ""
  private(set) var currentCourse: String?
  /// The average size of a part, read off the lesson in front. Kept when that
  /// lesson lands: the parts of one course are much the same size, and an estimate
  /// that disappeared for the first seconds of every lesson would flicker.
  private(set) var bytesPerPart: Int64 = 0
  /// The speed the queue is running at, handed in by the queue itself — it already
  /// smooths this for its own readout.
  private(set) var bytesPerSecond: Double = 0

  var total: Int64 { planned.values.reduce(0, +) }

  var completed: Int64 {
    planned.reduce(into: Int64(0)) { sum, entry in
      sum += min(done[entry.key] ?? 0, entry.value)
    }
  }

  /// The headline the system's card carries: the lesson coming down now, because
  /// that is the thing that changes as the queue moves. Between lessons it names
  /// the course, and with neither known it still says what the app is doing.
  var title: String {
    if !currentTitle.isEmpty { return "Downloading \(currentTitle)" }
    guard let course = currentCourse, !course.isEmpty else { return "Downloading lessons" }
    return "Downloading \(course)"
  }

  /// …and the line under it: what is left, how long that should take, and the course
  /// those lessons belong to.
  ///
  /// The order is the order a narrow card keeps — a long course name is the one
  /// thing here that can be cut off without losing the answer, so it goes last.
  var subtitle: String {
    var segments = [whatIsLeft]
    if let estimate = timeLeftPhrase { segments.append(estimate) }
    if !currentTitle.isEmpty, let course = currentCourse, !course.isEmpty {
      segments.append(course)
    }
    return segments.joined(separator: " · ")
  }

  private var whatIsLeft: String {
    switch lessonsLeft {
    case ..<1: return "Nothing left"
    case 1: return "Last lesson"
    default: return "\(lessonsLeft) lessons left"
    }
  }

  /// How long the rest should take: the parts still to fetch, at the size the lesson
  /// in front is showing and the speed the queue is running at. `nil` until a part
  /// has landed and a speed is known, because a card that guesses is worse than one
  /// that waits a few seconds for an answer.
  var secondsLeft: TimeInterval? {
    let parts = max(0, total - completed)
    guard parts > 0, bytesPerPart > 0, bytesPerSecond > 1 else { return nil }
    return Double(parts) * Double(bytesPerPart) / bytesPerSecond
  }

  var timeLeftPhrase: String? {
    guard let seconds = secondsLeft else { return nil }
    return "\(Self.duration(seconds)) left"
  }

  /// `under a minute`, `~12 min`, `~1 hr 5 min` — rounded, and marked as an
  /// estimate, because a part's size and the phone's speed both move.
  static func duration(_ seconds: TimeInterval) -> String {
    guard seconds >= 45 else { return "under a minute" }
    let minutes = Int((seconds / 60).rounded())
    guard minutes >= 60 else { return "~\(minutes) min" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "~\(hours) hr" : "~\(hours) hr \(rest) min"
  }

  var lessonsLeft: Int { max(0, planned.count - landed.count) }

  var hasWork: Bool { !planned.isEmpty }

  /// One lesson's share of the bar: its own part count when the manifest has said,
  /// its length until then, and never zero — a lesson with nothing known about it
  /// still counts as one part of work rather than disappearing from the total.
  static func plannedParts(for task: DownloadTask) -> Int64 {
    if task.segmentsTotal > 0 { return Int64(task.segmentsTotal) }
    let seconds = task.durationSec > 0 ? Double(task.durationSec) : secondsPerPart
    return max(1, Int64((seconds / secondsPerPart).rounded(.up)))
  }

  mutating func observe(_ tasks: [DownloadTask], bytesPerSecond: Double = 0) {
    var seen = Set<String>()
    for task in tasks {
      let known = planned[task.uuid] != nil
      // A lesson already on disk before this run began is not part of it: only a
      // row that is waiting, paused or in flight joins the plan.
      guard known || task.isActive else { continue }
      if !known { planned[task.uuid] = Self.plannedParts(for: task) }
      seen.insert(task.uuid)
      if task.state == .ready {
        landed.insert(task.uuid)
        done[task.uuid] = planned[task.uuid]
      } else {
        done[task.uuid] = Int64(task.segmentsDone)
      }
    }
    // A row the person cancelled, or one that failed, leaves the plan with it: its
    // parts are not coming, so counting them would leave the bar short for ever.
    for uuid in planned.keys.filter({ !seen.contains($0) }) {
      planned[uuid] = nil
      done[uuid] = nil
      landed.remove(uuid)
    }
    // The lesson in front: the one being written, or the next in line. Its own
    // title and course are what the card says, so a long queue can be read from the
    // lock screen rather than only counted.
    let queue = tasks.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
    let current = queue.first { $0.state == .downloading || $0.state == .remuxing }
      ?? queue.first
    currentTitle = current?.title ?? ""
    currentCourse = current?.courseTitle
    self.bytesPerSecond = max(0, bytesPerSecond)
    if let current, current.segmentsDone > 0, current.bytes > 0 {
      bytesPerPart = max(1, current.bytes / Int64(current.segmentsDone))
    }
  }
}

/// The system's answer to "a queue outlives the foreground".
///
/// iOS 26 keeps this process running for the length of a continued-processing
/// task — the assertion the download queue had been renewing by hand, with a
/// system card beside it. The card this app draws itself is the one that carries
/// the queue (the system's is one headline and one subtitle), so the task's own
/// card is welcome alongside ours rather than a replacement; what the task is
/// relied on for is the running process, without which neither card's numbers
/// move. Below iOS 26 there is nothing here and the queue falls back to
/// `BackgroundHold`, unchanged.
///
/// One task for the one queue: a second request would be a second task for the same
/// work, so a request that has been submitted is never submitted again.
@MainActor
final class ContinuedProcessing {
  static let shared = ContinuedProcessing()

  /// Declared in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`. The
  /// prefix is the app's own bundle id, which is the rule the scheduler enforces
  /// and what makes a wildcard unnecessary.
  static let identifier = "com.kyros.skillcappedlocal.download"

  private enum Phase { case idle, submitted, running }

  private var phase: Phase = .idle
  private var task: AnyObject?
  /// The numbers last handed over. A task that starts after the queue has already
  /// moved on is given the current ones rather than the ones it was asked for.
  private var latest: ContinuedRun?
  private var registered = false
  /// One report a second is plenty for a progress readout, and a lesson that
  /// changes in front is reported at once, because its name did.
  private static let reportInterval: TimeInterval = 1
  private var reportedAt: Date?
  private var reportedTitle = ""
  /// A refused request is retried rarely: parts settle many times a second and
  /// every attempt writes a journal line, so a burst would bury the reason.
  private static let submitInterval: TimeInterval = 10
  private var submittedAt: Date?

  /// iOS took the task away: the person cancelled it on its card, or the system
  /// needed the time for something else. Both are reported so the queue can fall
  /// back to the background assertion it uses on iOS 17–25.
  var onExpire: (@MainActor () -> Void)?
  /// Asked whenever the task starts or ends, so the queue can refresh the app's own
  /// lock-screen card at the moment its situation changed.
  var onStateChange: (@MainActor () -> Void)?

  /// Whether the system is keeping this app running for the queue *right now*.
  /// Only `running` counts: a request that has been submitted is still waiting for
  /// iOS to start it, and until it does the background assertion has to cover the
  /// gap — so this is the one question the assertion path asks, and it must not
  /// answer yes too early.
  var isCovering: Bool { phase == .running }

  static var isSupported: Bool {
    if #available(iOS 26.0, *) { return true }
    return false
  }

  /// Called once, from `AppDelegate`: registering after launch finishes is too late
  /// for the system to hand the task back.
  func register() {
    guard !registered else { return }
    registered = true
    guard #available(iOS 26.0, *) else {
      BackgroundJournal.shared.record("continued: no iOS 26 — the assertion stays in charge")
      return
    }
    let accepted = Continuous.register(identifier: Self.identifier) { [weak self] task in
      Task { @MainActor in self?.started(task) }
    }
    BackgroundJournal.shared.record(
      accepted
        ? "continued: registered \(Self.identifier)"
        : "continued: \(Self.identifier) is not in Info.plist — the queue stays on the assertion"
    )
  }

  /// The queue has work in this process: keep the numbers on the system's card in
  /// step, and ask for the task when there is not one yet.
  func keepAlive(_ run: ContinuedRun) {
    latest = run
    guard #available(iOS 26.0, *) else { return }
    guard phase == .running, let task = task as? BGContinuedProcessingTask else {
      submit(run)
      return
    }
    let now = Date()
    if run.title == reportedTitle, let reportedAt,
       now.timeIntervalSince(reportedAt) < Self.reportInterval { return }
    reportedAt = now
    reportedTitle = run.title
    Continuous.report(task, run)
  }

  /// Nothing is left to do: hand the time back. A request still waiting in the
  /// system's queue is withdrawn too, so a queue that drains between submission and
  /// start does not wake the app for nothing.
  func finish() {
    latest = nil
    guard #available(iOS 26.0, *) else { return }
    let was = phase
    guard was != .idle else { return }
    phase = .idle
    reportedAt = nil
    reportedTitle = ""
    submittedAt = nil
    if was == .running, let task = task as? BGContinuedProcessingTask {
      BackgroundJournal.shared.record("continued: finished")
      Continuous.complete(task, success: true)
    } else if was == .submitted {
      BackgroundJournal.shared.record("continued: withdrawn before it started")
      Continuous.cancel(identifier: Self.identifier)
    }
    task = nil
    onStateChange?()
  }

  private func submit(_ run: ContinuedRun) {
    guard #available(iOS 26.0, *) else { return }
    guard phase == .idle else { return }
    // Apple accepts a continued-processing request from a foreground app only. A
    // queue woken in the background keeps the assertion it already has instead.
    guard UIApplication.shared.applicationState == .active else { return }
    let now = Date()
    if let submittedAt, now.timeIntervalSince(submittedAt) < Self.submitInterval { return }
    submittedAt = now
    do {
      try Continuous.submit(
        identifier: Self.identifier,
        title: run.title,
        subtitle: run.subtitle
      )
      phase = .submitted
      BackgroundJournal.shared.record("continued: asked for \(run.lessonsLeft) lesson(s) left")
      onStateChange?()
    } catch {
      // A refusal is not fatal: the assertion path is what the queue used before
      // iOS 26 and it still works, so this is recorded rather than surfaced.
      BackgroundJournal.shared.record("continued: refused — \(error.localizedDescription)")
    }
  }

  private func started(_ any: AnyObject) {
    guard #available(iOS 26.0, *), let task = any as? BGContinuedProcessingTask else { return }
    phase = .running
    self.task = task
    BackgroundJournal.shared.record("continued: started")
    Continuous.arm(task) { [weak self] in
      Task { @MainActor in self?.expired() }
    }
    if let latest { Continuous.report(task, latest) }
    reportedAt = Date()
    reportedTitle = latest?.title ?? ""
    onStateChange?()
  }

  private func expired() {
    guard phase == .running else { return }
    phase = .idle
    if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
      Continuous.complete(task, success: false)
    }
    task = nil
    latest = nil
    reportedAt = nil
    reportedTitle = ""
    BackgroundJournal.shared.record("continued: taken away — the queue falls back to the assertion")
    onExpire?()
    onStateChange?()
  }
}

/// The iOS 26 calls, in one place, so nothing else in the app has to be written
/// against an API that does not exist on iOS 17.
@available(iOS 26.0, *)
private enum Continuous {
  static func register(
    identifier: String,
    handler: @escaping (BGContinuedProcessingTask) -> Void
  ) -> Bool {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let task = task as? BGContinuedProcessingTask else { return }
      handler(task)
    }
  }

  static func submit(identifier: String, title: String, subtitle: String) throws {
    let request = BGContinuedProcessingTaskRequest(
      identifier: identifier,
      title: title,
      subtitle: subtitle
    )
    try BGTaskScheduler.shared.submit(request)
  }

  /// The card's own progress bar, and the two lines above it.
  static func report(_ task: BGContinuedProcessingTask, _ run: ContinuedRun) {
    let total = max(1, run.total)
    task.progress.totalUnitCount = total
    task.progress.completedUnitCount = min(run.completed, total)
    task.updateTitle(run.title, subtitle: run.subtitle)
  }

  static func arm(_ task: BGContinuedProcessingTask, expired: @escaping () -> Void) {
    task.expirationHandler = expired
  }

  static func complete(_ task: BGContinuedProcessingTask, success: Bool) {
    task.setTaskCompleted(success: success)
  }

  static func cancel(identifier: String) {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
  }
}
