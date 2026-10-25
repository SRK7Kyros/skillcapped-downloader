import XCTest
@testable import SkillCappedLocal

final class PlayerChromeLayoutTests: XCTestCase {
  func testAPortraitPhoneFloatsTheThreeRarestControls() {
    for width in [320.0, 375, 393, 430] as [CGFloat] {
      XCTAssertTrue(
        PlayerChromeLayout.floatsControls(width: width),
        "a \(width)-point phone should float the rate and the queue steps"
      )
    }
  }

  func testAWindowWideEnoughKeepsOneRow() {
    for width in [667.0, 852, 932, 768, 1024] as [CGFloat] {
      XCTAssertFalse(
        PlayerChromeLayout.floatsControls(width: width),
        "a \(width)-point window has room for the whole row"
      )
    }
  }

  func testTheThresholdIsTheFloatingSideOfTheBoundary() {
    XCTAssertTrue(PlayerChromeLayout.floatsControls(width: 539))
    XCTAssertFalse(PlayerChromeLayout.floatsControls(width: 540))
  }

  func testAWidthNobodyHasMeasuredKeepsTheSingleRow() {
    XCTAssertFalse(PlayerChromeLayout.floatsControls(width: 0))
  }

  func testTheEdgeAwayFromTheCornerKeepsTheFlatMargin() {
    XCTAssertEqual(PlayerChromeLayout.away(safe: 0), PlayerChromeLayout.edgeMargin)
  }

  func testTheIslandOutranksTheMargin() {
    XCTAssertEqual(PlayerChromeLayout.away(safe: 59), 59, "the side inset a notched phone reports")
    XCTAssertEqual(PlayerChromeLayout.away(safe: 21), 21, "the home indicator")
    XCTAssertGreaterThan(PlayerChromeLayout.away(safe: 59), PlayerChromeLayout.edgeMargin)
  }

  func testACornerPushesTheRowInByWhatTheGlassTook() {
    let flat = PlayerChromeLayout.side(radius: 0, fromCorner: PlayerChromeLayout.edgeMargin)
    XCTAssertEqual(flat, PlayerChromeLayout.edgeMargin, "square glass needs no more than the margin")
    XCTAssertEqual(
      PlayerChromeLayout.side(radius: 62, fromCorner: 62),
      PlayerChromeLayout.edgeMargin,
      "the curve has ended by then, so the corner cannot push the row in further"
    )
    let inTheCorner = PlayerChromeLayout.side(radius: 62, fromCorner: PlayerChromeLayout.edgeMargin)
    XCTAssertGreaterThan(inTheCorner, PlayerChromeLayout.edgeMargin)
    XCTAssertLessThan(inTheCorner, PlayerChromeLayout.edgeMargin + 8, "a corner is a nudge, not a squeeze")
  }

  func testARowHigherUpTheEdgeKeepsLessRoomThanOneLowerDown() {
    // A phone on its side has no island to clear, so its header sits closer to
    // its corners than its bar does — and both are still inside the glass.
    let header = PlayerChromeLayout.side(
      radius: 62,
      fromCorner: PlayerChromeLayout.away(safe: 0)
    )
    let bar = PlayerChromeLayout.side(
      radius: 62,
      fromCorner: PlayerChromeLayout.away(safe: 21)
    )
    XCTAssertGreaterThan(header, bar)
  }

  func testTheCornerControlsSitOnTheGlassAndNotThroughIt() {
    let radius: CGFloat = 62
    let top = PlayerChromeLayout.away(safe: 0)
    let side = PlayerChromeLayout.side(radius: radius, fromCorner: top)
    XCTAssertTrue(
      DisplayCorner.isInside(x: side, y: top, radius: radius),
      "the close button's box must be on the glass, not off its corner"
    )
    XCTAssertGreaterThan(
      side + top,
      DisplayCorner.clearance(radius: radius) * 2,
      "and it keeps its air rather than touching the curve"
    )
  }
}
