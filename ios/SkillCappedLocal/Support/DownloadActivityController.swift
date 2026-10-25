import ActivityKit
import Foundation

/// The lock-screen face of the queue: one activity for the whole queue, never
/// one per lesson.
///
/// ActivityKit budgets updates, so they are throttled to at most one every two
/// seconds unless the lesson in front changes. A suspended app cannot update at
/// all — that is what `staleDate` is for: the card dims rather than pretending
/// its number is live.
@MainActor
final class DownloadActivityController {
  static let refreshInterval: TimeInterval = 2
  static let staleAfter: TimeInterval = 90

  private var activity: Activity<DownloadActivityAttributes>?
  private var lastUpdate = Date.distantPast
  private var lastState: DownloadActivityAttributes.ContentState?
  private var lastTitle = ""
  private var lastPaused = false

  var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  func show(_ summary: QueueSummary) {
    guard isAvailable else { return }
    let state = summary.state
    let now = Date()

    if let activity {
      let titleChanged = state.currentTitle != lastTitle
      let pausedChanged = state.paused != lastPaused
      let moved = abs(state.percent - (lastState?.percent ?? -1)) >= 0.005
      let due = titleChanged || pausedChanged
        || (moved && now.timeIntervalSince(lastUpdate) >= Self.refreshInterval)
      guard due else { return }
      remember(state, at: now)
      Task { await activity.update(content(state, at: now)) }
    } else if let carried = Activity<DownloadActivityAttributes>.activities.first {
      activity = carried
      remember(state, at: now)
      Task { await carried.update(content(state, at: now)) }
    } else {
      remember(state, at: now)
      activity = try? Activity.request(
        attributes: DownloadActivityAttributes(startedAt: now),
        content: content(state, at: now),
        pushType: nil
      )
    }
  }

  /// The queue has drained: keep the card for a moment on its last numbers so
  /// the finish is visible, then let the system dismiss it.
  func finish() {
    let done = finishedState()
    let active = Activity<DownloadActivityAttributes>.activities
    activity = nil
    lastState = nil
    lastTitle = ""
    lastPaused = false
    guard !active.isEmpty else { return }
    let content = ActivityContent(state: done, staleDate: nil)
    let dismissal = ActivityUIDismissalPolicy.after(Date().addingTimeInterval(6))
    Task {
      for item in active {
        await item.end(content, dismissalPolicy: dismissal)
      }
    }
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
