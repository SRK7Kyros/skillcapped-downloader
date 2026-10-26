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
  /// How long a hand-over is given with **no bytes** before it is called lost, by
  /// attempt. It escalates because the two failures look nothing alike: the first
  /// silence is a hung connection and a fresh one answers in a second, while a
  /// third consecutive silence is the network being gone and deserves the patience
  /// a stalled request used to get.
  ///
  /// The first window is what keeps the queue fast. Measured on 26 Oct 2026: a
  /// window of eight parts went quiet for 100 s, iOS reclaimed the
  /// continued-processing task, and the run collapsed to a window per wake. A
  /// deadline of two minutes could not answer in time, and — because it was the
  /// clock and not the transfer — could not tell that window from a healthy one
  /// either.
  static func silence(for attempt: Int) -> TimeInterval {
    switch attempt {
    case 1: return 30
    case 2: return 60
    default: return 120
    }
  }

  /// How often the byte count is sampled while the app is awake. A tick that never
  /// ran says nothing at all: a suspended app samples nothing, and that is exactly
  /// what makes the rule in `TransferSilence` safe across a suspension.
  static let sample: TimeInterval = 5

  /// Hand-overs one part is given before its lesson is failed. The retry loop in
  /// `SegmentDownloader.partSize` is what spends them.
  static let attempts = 3

  /// The watchdog gave up, as opposed to a request that failed for its own reason.
  /// Only this one means the queue suspected the system, and only this one is worth
  /// a journal line of its own: a 403 is the catalogue's answer, not a lost task.
  static func isLost(_ error: Error) -> Bool {
    (error as? URLError)?.code == .timedOut
  }
}

/// Whether a transfer is still moving.
///
/// A part used to be given a **wall-clock** deadline, which is wrong for a
/// background queue in both directions. The app is suspended between wakes, so the
/// moment iOS resumes it every pending part looks overdue at once and a healthy
/// window is cancelled — 26 Oct 2026: eight parts were declared dead 120 s after
/// the hand-over and one of them landed two seconds later. Meanwhile a transfer
/// that has genuinely hung is waited on for the whole window even though it stopped
/// receiving at the start of it.
///
/// Observing the byte count answers the question that matters — is this transfer
/// moving? — and answers it correctly across a suspension, because a tick that never
/// ran is not evidence of silence: bytes that arrived while the app slept reset the
/// window, and bytes that never came expire it at the first tick after the wake.
struct TransferSilence {
  private var lastBytes: Int64 = -1
  private var spokeAt: Date

  init(now: Date = Date()) {
    spokeAt = now
  }

  /// Notes what the transfer has received and answers whether it is lost.
  mutating func observe(_ bytes: Int64, at now: Date, lostAfter: TimeInterval) -> Bool {
    if bytes != lastBytes {
      lastBytes = bytes
      spokeAt = now
      return false
    }
    return now.timeIntervalSince(spokeAt) >= lostAfter
  }
}
