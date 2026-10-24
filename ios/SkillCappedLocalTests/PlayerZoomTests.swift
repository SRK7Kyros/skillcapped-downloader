import SwiftUI
import XCTest
@testable import SkillCappedLocal

final class PlayerZoomTests: XCTestCase {
  private let window = CGSize(width: 400, height: 200)

  func testAFitPictureCannotShrinkAndStopsAtFiveTimes() {
    XCTAssertEqual(PlayerZoom.clampScale(0.4), 1)
    XCTAssertEqual(PlayerZoom.clampScale(9), 5)
    XCTAssertEqual(PlayerZoom.clampScale(2.5), 2.5)
    XCTAssertEqual(PlayerZoom.clampScale(.nan), 1)
  }

  func testAPinchInTheMiddleGrowsAroundTheMiddle() {
    XCTAssertEqual(
      PlayerZoom.offset(starting: .zero, from: 1, to: 2, anchor: .center, size: window),
      .zero
    )
  }

  func testAPinchOnTheRightEdgeKeepsThatSpotStill() {
    let offset = PlayerZoom.offset(
      starting: .zero,
      from: 1,
      to: 2,
      anchor: UnitPoint(x: 1, y: 0.5),
      size: window
    )
    XCTAssertEqual(offset.width, -200, "the right edge grows outwards, so the picture moves left")
    XCTAssertEqual(offset.height, 0)
  }

  func testAPinchKeepsTheSpotItStartedOnWhileGrowingAgain() {
    let first = PlayerZoom.offset(
      starting: .zero,
      from: 1,
      to: 2,
      anchor: UnitPoint(x: 0.25, y: 0.5),
      size: window
    )
    let second = PlayerZoom.offset(
      starting: first,
      from: 2,
      to: 3,
      anchor: UnitPoint(x: 0.25, y: 0.5),
      size: window
    )
    let expected = PlayerZoom.offset(
      starting: .zero,
      from: 1,
      to: 3,
      anchor: UnitPoint(x: 0.25, y: 0.5),
      size: window
    )
    XCTAssertEqual(second.width, expected.width, accuracy: 0.001)
    XCTAssertEqual(second.height, expected.height, accuracy: 0.001)
  }

  func testAZoomedPictureCannotBeDraggedPastItsOwnEdge() {
    XCTAssertEqual(
      PlayerZoom.clamped(CGSize(width: 900, height: -900), scale: 2, size: window),
      CGSize(width: 200, height: -100)
    )
  }

  func testAFitPictureCannotBeDraggedAtAll() {
    XCTAssertEqual(
      PlayerZoom.clamped(CGSize(width: 40, height: 40), scale: 1, size: window),
      .zero
    )
  }

  func testAnEmptyZoomIsLeftAlone() {
    let offset = CGSize(width: 12, height: -4)
    XCTAssertEqual(
      PlayerZoom.offset(starting: offset, from: 0, to: 2, anchor: .center, size: window),
      offset
    )
  }
}
