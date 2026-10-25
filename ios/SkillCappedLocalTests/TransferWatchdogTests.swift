import XCTest
@testable import SkillCappedLocal

/// The queue waits for the system to hand a part back, and nothing tells the app
/// when one is dropped, so the wait has to give up on its own. These pin the two
/// numbers that decide how long that takes and how many times a part is tried.
final class TransferWatchdogTests: XCTestCase {
  func testTheDeadlineOutlastsTheSessionsOwnRequestTimeout() {
    // The session retries a stalled request itself at 60 s; a deadline under that
    // would cancel a transfer that was about to be answered.
    XCTAssertGreaterThan(TransferWatchdog.deadline, .seconds(60))
  }

  func testTheDeadlineIsShortEnoughToCostMinutesNotTheRun() {
    XCTAssertLessThanOrEqual(TransferWatchdog.deadline, .seconds(300))
  }

  func testAPartIsGivenMoreThanOneHandOver() {
    XCTAssertGreaterThanOrEqual(TransferWatchdog.attempts, 2)
  }

  func testOnlyATimedOutTransferCountsAsLost() {
    XCTAssertTrue(TransferWatchdog.isLost(URLError(.timedOut)))
    XCTAssertFalse(TransferWatchdog.isLost(URLError(.networkConnectionLost)))
    XCTAssertFalse(TransferWatchdog.isLost(URLError(.notConnectedToInternet)))
    XCTAssertFalse(TransferWatchdog.isLost(CancellationError()))
    XCTAssertFalse(TransferWatchdog.isLost(DownloadError.segment(index: 4, status: 403)))
  }
}
