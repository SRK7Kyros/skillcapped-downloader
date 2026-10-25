import ActivityKit
import Foundation
import UIKit

/// Which cards this app may keep drawing on.
///
/// An ended or dismissed activity is still listed by `Activity.activities` for a
/// moment, and adopting one answers nothing: every later update goes to a card the
/// system has already taken down, so the lock screen stays empty for the life of
/// the process while the queue looks perfectly healthy from inside.
enum ActivityLiveness {
  static func isLive(_ state: Activity<DownloadActivityAttributes>.ActivityState) -> Bool {
    switch state {
    case .active, .stale: return true
    case .ended, .dismissed: return false
    }
  }
}

/// The lock-screen face of the queue: one activity for the whole queue, never
/// one per lesson.
///
/// ActivityKit budgets updates, so they are throttled to at most one every two
/// seconds unless the lesson in front changes. A suspended app cannot update at
/// all — that is what `staleDate` is for: the card dims rather than pretending
/// its number is live.
///
/// `trouble` is the other half of the same job: when no card is on the lock screen
/// the app can say why rather than leaving it a mystery.
@MainActor
final class DownloadActivityController {
  static let refreshInterval: TimeInterval = 2
  static let staleAfter: TimeInterval = 90

  private var activity: Activity<DownloadActivityAttributes>?
  private var lastUpdate = Date.distantPast
  private var lastState: DownloadActivityAttributes.ContentState?
  private var lastTitle = ""
  private var lastPaused = false
  /// The queue as last handed over. Apple only lets an app start a card while it
  /// is in the foreground, so a queue woken in the background keeps its summary
  /// and asks again the moment the app comes forward.
  private var lastSummary: QueueSummary?

  /// Why no card is on the lock screen, in words that can be shown as they are.
  /// `nil` while it is there.
  private(set) var trouble: String?

  init() {
    _ = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.retry() }
    }
  }

  var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  func show(_ summary: QueueSummary) {
    lastSummary = summary
    guard isAvailable else {
      trouble = "Live Activities are off for SkillCapped Local — turn on Settings › SkillCapped Local › Live Activities."
      return
    }
    let state = summary.state
    let now = Date()

    if let live = liveActivity() {
      guard due(state, at: now) else {
        trouble = nil
        return
      }
      remember(state, at: now)
      Task { await live.update(content(state, at: now)) }
      trouble = nil
      return
    }

    guard UIApplication.shared.applicationState == .active else { return }
    remember(state, at: now)
    do {
      activity = try Activity.request(
        attributes: DownloadActivityAttributes(startedAt: now),
        content: content(state, at: now),
        pushType: nil
      )
      trouble = nil
    } catch {
      trouble = "The download card could not start: \(error.localizedDescription)"
    }
  }

  /// The queue has drained: keep the card for a moment on its last numbers so
  /// the finish is visible, then let the system dismiss it.
  func finish() {
    let done = finishedState()
    let active = Activity<DownloadActivityAttributes>.activities
    activity = nil
    lastSummary = nil
    lastState = nil
    lastTitle = ""
    lastPaused = false
    trouble = nil
    guard !active.isEmpty else { return }
    let content = ActivityContent(state: done, staleDate: nil)
    let dismissal = ActivityUIDismissalPolicy.after(Date().addingTimeInterval(6))
    Task {
      for item in active {
        await item.end(content, dismissalPolicy: dismissal)
      }
    }
  }

  /// The card this app can keep drawing on, ending any the system already took
  /// down so a later pass cannot adopt one again.
  private func liveActivity() -> Activity<DownloadActivityAttributes>? {
    if let activity {
      if ActivityLiveness.isLive(activity.activityState) { return activity }
      self.activity = nil
    }
    let all = Activity<DownloadActivityAttributes>.activities
    let live = all.first { ActivityLiveness.isLive($0.activityState) }
    let gone = all.filter { !ActivityLiveness.isLive($0.activityState) }
    if !gone.isEmpty {
      Task {
        for item in gone {
          await item.end(nil, dismissalPolicy: .immediate)
        }
      }
    }
    activity = live
    return live
  }

  private func retry() {
    guard let lastSummary else { return }
    show(lastSummary)
  }

  private func due(_ state: DownloadActivityAttributes.ContentState, at now: Date) -> Bool {
    let titleChanged = state.currentTitle != lastTitle
    let pausedChanged = state.paused != lastPaused
    let moved = abs(state.percent - (lastState?.percent ?? -1)) >= 0.005
    return titleChanged || pausedChanged
      || (moved && now.timeIntervalSince(lastUpdate) >= Self.refreshInterval)
  }

  private func remember(_ state: DownloadActivityAttributes.ContentState, at now: Date) {
    lastUpdate = now
    lastTitle = state.currentTitle
    lastPaused = state.paused
    lastState = state
  }

  private func content(
    _ state: DownloadActivityAttributes.ContentState,
    at now: Date
  ) -> ActivityContent<DownloadActivityAttributes.ContentState> {
    ActivityContent(state: state, staleDate: now.addingTimeInterval(Self.staleAfter))
  }

  private func finishedState() -> DownloadActivityAttributes.ContentState {
    guard var done = lastState else {
      return DownloadActivityAttributes.ContentState(
        lessonsLeft: 0,
        segmentsDone: 0,
        segmentsTotal: 0,
        bytesDone: 0,
        currentTitle: "Downloads finished",
        currentCourse: nil,
        paused: false
      )
    }
    done.lessonsLeft = 0
    done.paused = false
    if done.segmentsTotal > 0 { done.segmentsDone = done.segmentsTotal }
    return done
  }
}
