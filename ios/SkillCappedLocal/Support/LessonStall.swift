import Foundation

/// How long the lesson in flight is given before the queue stops trusting it.
///
/// `TransferWatchdog` bounds one part; this bounds the lesson. They are not the
/// same failure. A lesson also spends time on things that are not a part at all —
/// the rendition listing, the part count, the merge, the move into the library —
/// and every one of those runs inside the single task `DownloadManager.pump`
/// started. `pump` refuses to start anything while that task is alive, so an await
/// inside the lesson that nothing ever answers holds the whole queue: no next
/// lesson, no refill, and foregrounding changes nothing, because the scene change
/// only calls `pump`, which finds that same task still holding the slot.
///
/// A healthy lesson says something every few seconds — a part settles in about a
/// second on this CDN and each one reports — so minutes of complete silence is not
/// a slow lesson. It is a queue that would wait for ever.
enum LessonStall {
  /// Four minutes: twice the slowest gap ever measured between windows delivered to
  /// a *suspended* app (42–114 s), so a background lesson that is merely waiting on
  /// the system is not mistaken for a dead one, and short enough that a stuck lesson
  /// costs minutes rather than the night.
  static let limit: TimeInterval = 240

  /// A merge reports once when it starts and once when it lands, so its silence
  /// says nothing about its health — and restarting it throws away the merge that
  /// was nearly finished. Fifteen minutes of no completion is a wedged merge.
  static let mergeLimit: TimeInterval = 900

  /// Attempts one lesson is given before it is failed instead of restarted, so a
  /// lesson that stalls every time cannot spin the queue for ever. A restart is
  /// cheap — the parts already on disk are kept and skipped — so two are spent
  /// before the queue moves on to the next lesson.
  static let restarts = 2

  /// Nothing has been heard from the lesson since `last`.
  static func isStalled(
    since last: Date?,
    now: Date = Date(),
    limit: TimeInterval = LessonStall.limit
  ) -> Bool {
    guard let last else { return false }
    return now.timeIntervalSince(last) > limit
  }

  /// Another attempt is allowed; past this the lesson is failed so the queue moves.
  static func mayRestart(after attempts: Int) -> Bool {
    attempts < restarts
  }

  /// The one sentence the journal and the failed row both use, so a stall read off
  /// the phone says the same thing wherever it is read.
  static func sentence(seconds: Int, restarting: Bool) -> String {
    restarting
      ? "no progress for \(seconds) s — starting it again"
      : "no progress for \(seconds) s — given up on"
  }
}
