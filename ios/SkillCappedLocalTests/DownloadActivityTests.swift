import ActivityKit
import XCTest

@testable import SkillCappedLocal

/// The two rules that decide whether the lock-screen card shows at all, and
/// whether the app stays awake between batches. Both were broken in 1.22.0 and
/// neither is visible from the outside: a card that goes nowhere looks exactly
/// like a card that was never asked for.
final class DownloadActivityTests: XCTestCase {
  func testACardTheSystemStillDrawsIsReused() {
    XCTAssertTrue(ActivityLiveness.isLive(.active))
    XCTAssertTrue(ActivityLiveness.isLive(.stale))
  }

  func testACardTheSystemHasTakenDownIsNotAdopted() {
    XCTAssertFalse(ActivityLiveness.isLive(.ended))
    XCTAssertFalse(ActivityLiveness.isLive(.dismissed))
  }

  func testABatchThatLandedKeepsTheAppAwakeWhilePartsAreStillWanted() {
    XCTAssertTrue(TransferHandover.keepsWorking([.downloading]))
    XCTAssertTrue(TransferHandover.keepsWorking([.ready, .queued]))
  }

  func testAQueueWithNothingToStartDoesNotHoldTheAppOpen() {
    XCTAssertFalse(TransferHandover.keepsWorking([]))
    XCTAssertFalse(TransferHandover.keepsWorking([.ready, .failed, .cancelled]))
    XCTAssertFalse(TransferHandover.keepsWorking([.paused]))
    XCTAssertFalse(TransferHandover.keepsWorking([.remuxing]))
  }
}
