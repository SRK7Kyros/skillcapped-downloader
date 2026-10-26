import XCTest
@testable import SkillCappedLocal

/// The queue waits for the system to hand a part back, and nothing tells the app
/// when one is dropped, so the wait has to give up on its own. These pin the two
/// numbers that decide how long that takes and how many times a part is tried.
final class TransferWatchdogTests: XCTestCase {
  func testTheFirstHandOverIsGivenAShortWindow() {
    // The common failure is one hung connection, and a fresh one answers in a
    // second — so the first silence must be caught while the app can still report
    // progress, because a continued-processing task is reclaimed when it stops.
    XCTAssertLessThanOrEqual(TransferWatchdog.silence(for: 1), 30)
  }

  func testEachHandOverIsGivenLongerThanTheLast() {
    // A third consecutive silence is the network being gone, not a hung socket.
    XCTAssertLessThan(TransferWatchdog.silence(for: 1), TransferWatchdog.silence(for: 2))
    XCTAssertLessThanOrEqual(TransferWatchdog.silence(for: 2), TransferWatchdog.silence(for: 3))
    XCTAssertLessThanOrEqual(TransferWatchdog.silence(for: 3), 120)
  }

  func testTheSampleSitsWellInsideTheShortestWindow() {
    XCTAssertGreaterThanOrEqual(TransferWatchdog.sample, 1)
    XCTAssertLessThanOrEqual(TransferWatchdog.sample * 2, TransferWatchdog.silence(for: 1))
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

  // MARK: - TransferSilence

  func testATransferThatKeepsReceivingIsNeverLost() {
    let start = Date()
    var silence = TransferSilence(now: start)
    for tick in 1...120 {
      let now = start.addingTimeInterval(Double(tick) * TransferWatchdog.sample)
      XCTAssertFalse(silence.observe(Int64(tick) * 1_000, at: now, lostAfter: 30))
    }
  }

  func testASilentTransferIsLostOnceTheWindowHasPassed() {
    let start = Date()
    var silence = TransferSilence(now: start)
    XCTAssertFalse(silence.observe(0, at: start.addingTimeInterval(5), lostAfter: 30))
    XCTAssertFalse(silence.observe(0, at: start.addingTimeInterval(30), lostAfter: 30))
    XCTAssertTrue(silence.observe(0, at: start.addingTimeInterval(35), lostAfter: 30))
  }

  func testBytesThatArriveWhileTheAppWasSuspendedAreNotASilence() {
    // The tick that never ran is the whole point: the app was asleep, and the
    // transfer answered while it was away. A wall-clock deadline called this lost.
    let start = Date()
    var silence = TransferSilence(now: start)
    XCTAssertFalse(silence.observe(0, at: start.addingTimeInterval(5), lostAfter: 30))
    XCTAssertFalse(silence.observe(2_700_000, at: start.addingTimeInterval(120), lostAfter: 30))
    XCTAssertFalse(silence.observe(2_700_000, at: start.addingTimeInterval(125), lostAfter: 30))
  }

  func testAPartThatReceivedNothingWhileTheAppWasSuspendedIsLostAtTheFirstTick() {
    let start = Date()
    var silence = TransferSilence(now: start)
    XCTAssertFalse(silence.observe(0, at: start.addingTimeInterval(5), lostAfter: 30))
    XCTAssertTrue(silence.observe(0, at: start.addingTimeInterval(120), lostAfter: 30))
  }

  func testTheFirstObservationIsNeverSilence() {
    // The task is brand new; nothing may be read into the bytes it has not sent yet.
    var silence = TransferSilence(now: Date())
    XCTAssertFalse(silence.observe(0, at: Date(), lostAfter: 1))
  }
}
