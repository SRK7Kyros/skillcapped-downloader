import CoreGraphics
import XCTest
@testable import SkillCappedLocal

final class PosterShapeTests: XCTestCase {
  func testThePosterKeepsItsOwnPortraitShape() {
    let ratio = PosterShape.ratio(width: 576, height: 912)
    XCTAssertEqual(ratio!, PosterShape.portrait, accuracy: 0.0001)
  }

  func testAStillIsLandscape() {
    XCTAssertEqual(PosterShape.ratio(of: CGSize(width: 1_920, height: 1_080))!, PosterShape.landscape, accuracy: 0.0001)
  }

  func testASizeThatDescribesNoBoxHasNoShape() {
    XCTAssertNil(PosterShape.ratio(width: 0, height: 918))
    XCTAssertNil(PosterShape.ratio(width: 576, height: 0))
    XCTAssertNil(PosterShape.ratio(width: -10, height: 918))
    XCTAssertNil(PosterShape.ratio(width: .infinity, height: 918))
    XCTAssertNil(PosterShape.ratio(width: 576, height: .nan))
  }

  func testTheStandInShapeFollowsTheKindOfArt() {
    XCTAssertEqual(PosterShape.fallback(course: true), PosterShape.portrait)
    XCTAssertEqual(PosterShape.fallback(course: false), PosterShape.landscape)
  }

  func testTheHeightABoxNeeds() {
    XCTAssertEqual(PosterShape.height(width: 180, ratio: PosterShape.portrait), 285, accuracy: 0.01)
    XCTAssertEqual(PosterShape.height(width: 320, ratio: PosterShape.landscape), 180, accuracy: 0.01)
  }

  func testAWidthThatCannotMakeABoxIsZeroHigh() {
    XCTAssertEqual(PosterShape.height(width: 0, ratio: PosterShape.landscape), 0)
    XCTAssertEqual(PosterShape.height(width: 100, ratio: 0), 0)
  }
}
