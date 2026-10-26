import Foundation

/// The queue in the numbers a Live Activity draws.
///
/// Pure, so the arithmetic and the wording are testable without ActivityKit:
/// the activity itself only carries this to the lock screen.
struct QueueSummary: Equatable {
  let lessonsLeft: Int
  let segmentsDone: Int
  let segmentsTotal: Int
  let bytesDone: Int64
  let currentTitle: String
  let currentCourse: String?
  let paused: Bool
  /// Filled from the queue's own estimate, which is only known once a part has
  /// landed; `nil` before that.
  var timeLeft: String? = nil

  var percent: Double {
    guard segmentsTotal > 0 else { return 0 }
    return min(1, Double(segmentsDone) / Double(segmentsTotal))
  }

  var state: DownloadActivityAttributes.ContentState {
    DownloadActivityAttributes.ContentState(
      lessonsLeft: lessonsLeft,
      segmentsDone: segmentsDone,
      segmentsTotal: segmentsTotal,
      bytesDone: bytesDone,
      currentTitle: currentTitle,
      currentCourse: currentCourse,
      paused: paused,
      timeLeft: timeLeft
    )
  }

  /// Numbers for a request made with nothing to download — the Settings readout's
  /// own card, so a refusal can be provoked and read while the queue is idle.
  static let preview = QueueSummary(
    lessonsLeft: 1,
    segmentsDone: 42,
    segmentsTotal: 100,
    bytesDone: 12_000_000,
    currentTitle: "Card check",
    currentCourse: "Live Activity",
    paused: false
  )

  /// `nil` when nothing is left to fetch, which is when the activity ends.
  static func of(_ tasks: [DownloadTask]) -> QueueSummary? {
    let queue = tasks.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
    guard let first = queue.first else { return nil }
    let current = queue.first { $0.state == .downloading || $0.state == .remuxing } ?? first
    return QueueSummary(
      lessonsLeft: queue.count,
      segmentsDone: queue.reduce(0) { $0 + $1.segmentsDone },
      segmentsTotal: queue.reduce(0) { $0 + $1.segmentsTotal },
      bytesDone: queue.reduce(0) { $0 + $1.bytes },
      currentTitle: current.title,
      currentCourse: current.courseTitle,
      paused: !queue.contains { $0.state == .downloading || $0.state == .remuxing || $0.state == .queued }
    )
  }
}
