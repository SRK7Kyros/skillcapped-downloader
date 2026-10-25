import Foundation

/// How long a part the system was handed is given before the queue stops waiting.
///
/// A lesson awaits one `BackgroundTransfer.wait` per part, and every one of those
/// waits lives inside the single task `DownloadManager.pump` runs. A wait that
/// never returns is therefore not a slow lesson — it is a queue that is dead until
/// the app is killed and reopened, because `pump` refuses to start anything while
/// that task is alive (`guard runner == nil`) and nothing else can clear it.
///
/// The system owns the transfers, so nothing tells the app when one is dropped. A
/// part on this CDN is two or three megabytes and the slowest measured is about a
/// second, so two minutes of silence is not a slow transfer: it is a task the
/// daemon lost, or a session that no longer owns it. The only move that can still
/// make progress is to cancel the task and hand the part over again.
enum TransferWatchdog {
  /// Longer than the session's own 60 s request timeout, so a stalled request is
  /// given the session's own retry first; short enough that a lost part costs a
  /// couple of minutes rather than the rest of the run.
  static let deadline: Duration = .seconds(120)

  /// Hand-overs one part is given before its lesson is failed. The retry loop in
  /// `SegmentDownloader.partSize` is what spends them.
  static let attempts = 3

  /// The deadline ran out, as opposed to a request that failed for its own reason.
  /// Only this one means the queue suspected the system, and only this one is worth
  /// a journal line of its own: a 403 is the catalogue's answer, not a lost task.
  static func isLost(_ error: Error) -> Bool {
    (error as? URLError)?.code == .timedOut
  }
}
