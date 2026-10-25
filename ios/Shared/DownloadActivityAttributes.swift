import ActivityKit
import Foundation

/// What the Live Activity draws: the download queue, never a single lesson.
///
/// Compiled into the app and into the widget extension, because the two sides
/// must agree on the shape exactly — that is the whole contract between them.
struct DownloadActivityAttributes: ActivityAttributes {
  /// The queue's own clock, fixed when the activity starts.
  var startedAt: Date

  struct ContentState: Codable, Hashable {
    /// Lessons still to fetch, the one in front included.
    var lessonsLeft: Int
    var segmentsDone: Int
    var segmentsTotal: Int
    var bytesDone: Int64
    var currentTitle: String
    var currentCourse: String?
    var paused: Bool

    /// The queue's bar: parts landed over parts known. A lesson whose part count
    /// has not been read yet contributes nothing, which is why the bar can jump
    /// when the next manifest arrives.
    var percent: Double {
      guard segmentsTotal > 0 else { return 0 }
      return min(1, Double(segmentsDone) / Double(segmentsTotal))
    }
  }
}
