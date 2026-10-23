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
}
