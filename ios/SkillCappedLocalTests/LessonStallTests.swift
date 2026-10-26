import XCTest
@testable import SkillCappedLocal

final class LessonStallTests: XCTestCase {
  func testALessonThatHasSaidNothingIsNotStalledUntilTheLimitHasPassed() {
    let last = Date(timeIntervalSince1970: 1_000_000)
    XCTAssertFalse(
      LessonStall.isStalled(since: last, now: last.addingTimeInterval(LessonStall.limit - 1))
    )
    XCTAssertTrue(
      LessonStall.isStalled(since: last, now: last.addingTimeInterval(LessonStall.limit + 1))
    )
  }

  func testALessonThatHasNotStartedReportingYetIsNeverStalled() {
    XCTAssertFalse(LessonStall.isStalled(since: nil))
  }

  func testTheLimitOutlastsTheSlowestGapBetweenWindowsForASuspendedApp() {
    // Measured: a suspended app is handed one window 42–114 s apart. A lesson that
    // is merely waiting on the system must not be restarted for it, so the limit
    // has to sit well clear of that gap.
    XCTAssertGreaterThan(LessonStall.limit, 114)
  }

  func testTheLessonLimitOutlastsThePartWatchdogSoTheTwoDoNotRace() {
    // A part the system never hands back is caught by its own deadline first; the
    // lesson-level check is the backstop for everything that is not a part.
    XCTAssertGreaterThan(LessonStall.limit, Double(TransferWatchdog.deadline.components.seconds))
  }

  func testAMergeIsGivenLongerThanATransferBecauseItReportsOnlyAtItsEnds() {
    XCTAssertGreaterThan(LessonStall.mergeLimit, LessonStall.limit)
  }

  func testOneLessonIsRestartedTwiceAndThenGivenUpOn() {
    XCTAssertTrue(LessonStall.mayRestart(after: 0))
    XCTAssertTrue(LessonStall.mayRestart(after: LessonStall.restarts - 1))
    XCTAssertFalse(LessonStall.mayRestart(after: LessonStall.restarts))
    XCTAssertFalse(LessonStall.mayRestart(after: LessonStall.restarts + 5))
  }

  func testTheSentenceSaysWhetherItIsStartingAgainOrGivingUp() {
    XCTAssertEqual(
      LessonStall.sentence(seconds: 244, restarting: true),
      "no progress for 244 s — starting it again"
    )
    XCTAssertEqual(
      LessonStall.sentence(seconds: 611, restarting: false),
      "no progress for 611 s — given up on"
    )
  }
}
