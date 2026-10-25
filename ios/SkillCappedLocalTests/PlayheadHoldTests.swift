import XCTest
@testable import SkillCappedLocal

final class PlayheadHoldTests: XCTestCase {
  func testTheBarFollowsTheClockWhenNothingIsHeld() {
    var hold = PlayheadHold()
    XCTAssertEqual(hold.follow(12), 12)
    XCTAssertEqual(hold.follow(12.25), 12.25)
  }

  func testAClockTickCannotMoveTheBarWhileAFingerChooses() {
    var hold = PlayheadHold()
    hold.choose()
    XCTAssertNil(hold.follow(12))
    XCTAssertNil(hold.follow(12.25))
  }

  func testTheTicksBeforeASeekLandsCannotPullTheBarBack() {
    var hold = PlayheadHold()
    hold.choose()
    _ = hold.follow(12)
    hold.seek(300)

    XCTAssertNil(hold.follow(12))
    XCTAssertNil(hold.follow(12.25))
    XCTAssertTrue(hold.isHeld)
  }

  func testTheTickThatAgreesWithTheSeekTakesTheBarBack() {
    var hold = PlayheadHold()
    hold.seek(300)
    _ = hold.follow(12)

    XCTAssertEqual(hold.follow(300), 300)
    XCTAssertFalse(hold.isHeld)
    XCTAssertEqual(hold.follow(300.25), 300.25)
  }

  func testASeekLandedWithinTheToleranceStillReleases() {
    var hold = PlayheadHold()
    hold.seek(300)
    XCTAssertEqual(hold.follow(300 + PlayheadHold.landed), 300 + PlayheadHold.landed)
  }

  func testASeekJustPastTheToleranceKeepsHolding() {
    var hold = PlayheadHold()
    hold.seek(300)
    XCTAssertNil(hold.follow(300 + PlayheadHold.landed + 0.01))
  }

  func testAFingerOutranksASeekStillOnItsWay() {
    var hold = PlayheadHold()
    hold.seek(300)
    hold.choose()

    XCTAssertNil(hold.follow(300))
    XCTAssertTrue(hold.isHeld)
  }

  func testAnExpiredHoldOnlyClearsItsOwnTarget() {
    var hold = PlayheadHold()
    hold.seek(300)
    hold.expire(120)
    XCTAssertTrue(hold.isHeld)

    hold.expire(300)
    XCTAssertFalse(hold.isHeld)
  }

  func testANonFiniteReadingChangesNothing() {
    var hold = PlayheadHold()
    XCTAssertNil(hold.follow(.nan))
    XCTAssertNil(hold.follow(.infinity))

    hold.seek(300)
    XCTAssertNil(hold.follow(.nan))
    XCTAssertTrue(hold.isHeld)
  }
}
