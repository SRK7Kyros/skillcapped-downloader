import XCTest
@testable import SkillCappedLocal

final class PlayerGesturesTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_000_000)

  func testDoubleTapsKeepAddingFiveSeconds() {
    var burst = SkipBurst()
    XCTAssertEqual(burst.tap(backward: false, at: start), 5)
    XCTAssertEqual(burst.tap(backward: false, at: start.addingTimeInterval(0.5)), 10)
    XCTAssertEqual(burst.tap(backward: false, at: start.addingTimeInterval(1)), 15)
  }

  func testAPauseRestartsTheCount() {
    var burst = SkipBurst()
    XCTAssertEqual(burst.tap(backward: false, at: start), 5)
    XCTAssertEqual(burst.tap(backward: false, at: start.addingTimeInterval(3)), 5)
  }

  func testTappingTheOtherSideRestartsTheCount() {
    var burst = SkipBurst()
    XCTAssertEqual(burst.tap(backward: false, at: start), 5)
    XCTAssertEqual(burst.tap(backward: true, at: start.addingTimeInterval(0.2)), -5)
  }

  func testBackwardBurstsStayNegative() {
    var burst = SkipBurst()
    XCTAssertEqual(burst.tap(backward: true, at: start), -5)
    XCTAssertEqual(burst.tap(backward: true, at: start.addingTimeInterval(0.4)), -10)
  }

  func testResetForgetsTheBurst() {
    var burst = SkipBurst()
    _ = burst.tap(backward: false, at: start)
    burst.reset()
    XCTAssertEqual(burst.tap(backward: false, at: start.addingTimeInterval(0.1)), 5)
  }

  func testTheLeftHalfIsBrightnessAndTheRightIsVolume() {
    XCTAssertEqual(PlayerMath.channel(x: 10, width: 390), .brightness)
    XCTAssertEqual(PlayerMath.channel(x: 194, width: 390), .brightness)
    XCTAssertEqual(PlayerMath.channel(x: 196, width: 390), .volume)
    XCTAssertEqual(PlayerMath.channel(x: 380, width: 390), .volume)
  }

  func testADragAcrossTheWidthIsTheWholeLesson() {
    XCTAssertEqual(PlayerMath.seek(from: 100, translation: 0, width: 390, duration: 600), 100)
    XCTAssertEqual(PlayerMath.seek(from: 100, translation: 195, width: 390, duration: 600), 400)
    XCTAssertEqual(PlayerMath.seek(from: 100, translation: -195, width: 390, duration: 600), 0)
  }

  func testSeekingStaysInsideTheLesson() {
    XCTAssertEqual(PlayerMath.seek(from: 10, translation: -1_000, width: 390, duration: 600), 0)
    XCTAssertEqual(PlayerMath.seek(from: 590, translation: 1_000, width: 390, duration: 600), 600)
  }

  func testSeekingWithoutADurationLeavesThePlayheadAlone() {
    XCTAssertEqual(PlayerMath.seek(from: 10, translation: 50, width: 390, duration: 0), 10)
    XCTAssertEqual(PlayerMath.seek(from: 10, translation: 50, width: 0, duration: 600), 10)
  }

  func testLiftingTheFingerRaisesALevel() {
    XCTAssertEqual(PlayerMath.level(from: 0.5, translation: 0, height: 800), 0.5, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.level(from: 0.5, translation: -400, height: 800), 1, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.level(from: 0.5, translation: 400, height: 800), 0, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.level(from: 0.9, translation: -2_000, height: 800), 1, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.level(from: 0.1, translation: 2_000, height: 800), 0, accuracy: 0.0001)
  }

  func testALevelWithoutAHeightDoesNotMove() {
    XCTAssertEqual(PlayerMath.level(from: 0.5, translation: 400, height: 0), 0.5, accuracy: 0.0001)
  }

  func testTheBarFractions() {
    XCTAssertEqual(PlayerMath.fraction(position: 150, duration: 600), 0.25, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.fraction(position: 900, duration: 600), 1, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.fraction(position: -5, duration: 600), 0, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.fraction(position: 10, duration: 0), 0, accuracy: 0.0001)
  }

  func testTappingTheBarAsksForThatPoint() {
    XCTAssertEqual(PlayerMath.seconds(x: 195, width: 390, duration: 600), 300, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.seconds(x: -20, width: 390, duration: 600), 0, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.seconds(x: 900, width: 390, duration: 600), 600, accuracy: 0.0001)
    XCTAssertEqual(PlayerMath.seconds(x: 100, width: 390, duration: 0), 0, accuracy: 0.0001)
  }

  func testTheClockReadsLikeAClock() {
    XCTAssertEqual(PlayerMath.clock(0), "0:00")
    XCTAssertEqual(PlayerMath.clock(5), "0:05")
    XCTAssertEqual(PlayerMath.clock(65.4), "1:05")
    XCTAssertEqual(PlayerMath.clock(3_725), "1:02:05")
  }

  func testAnUnknownDurationShowsDashes() {
    XCTAssertEqual(PlayerMath.clock(.nan), "--:--")
    XCTAssertEqual(PlayerMath.clock(.infinity), "--:--")
    XCTAssertEqual(PlayerMath.clock(-3), "--:--")
    XCTAssertEqual(PlayerMath.clock(400_000), "--:--")
  }
}
