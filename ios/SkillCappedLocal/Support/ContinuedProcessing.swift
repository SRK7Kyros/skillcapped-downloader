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

  var total: Int64 { planned.values.reduce(0, +) }

  var completed: Int64 {
    planned.reduce(into: Int64(0)) { sum, entry in
      sum += min(done[entry.key] ?? 0, entry.value)
    }
  }

  /// The headline the system's card carries.
  var title: String {
    guard let course = currentCourse, !course.isEmpty else { return "Downloading lessons" }
    return "Downloading \(course)"
  }

  /// …and the line under it: which lesson is coming down, and how much of the
  /// queue is left behind it.
  var subtitle: String {
    let left = lessonsLeft
    let remaining: String
    switch left {
    case ..<1: remaining = "Nothing left"
    case 1: remaining = "Last lesson"
    default: remaining = "\(left) lessons left"
    }
    return currentTitle.isEmpty ? remaining : "\(currentTitle) · \(remaining)"
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

  mutating func observe(_ tasks: [DownloadTask]) {
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
  }
}

/// The system's own answer to "a queue outlives the foreground".
///
/// iOS 26 keeps this process running for the length of a continued-processing
/// task and draws its own card saying so, which is exactly the two things the
/// download queue had been rebuilding by hand: an assertion that keeps the app
/// awake, and a progress card that is the system's rather than ours. Below iOS 26
/// there is nothing here and the queue falls back to `BackgroundHold`, unchanged.
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

  /// iOS took the task away: the person cancelled it on its card, or the system
  /// needed the time for something else. Both mean stop — carrying on would
  /// download behind a card that is no longer there.
  var onExpire: (@MainActor () -> Void)?
  /// Asked whenever the task starts or ends, because the app draws its own
  /// lock-screen card only while the system is not drawing one.
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
    BackgroundJournal.shared.record("continued: taken away — the queue is paused")
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
