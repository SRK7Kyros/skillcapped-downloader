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

  func testAWindowWinsOverWhateverArtArrived() {
    let taller = CGFloat(500) / 1000
    XCTAssertEqual(PosterShape.window(art: taller, fallback: PosterShape.portrait, window: PosterShape.portrait), PosterShape.portrait)
    XCTAssertEqual(PosterShape.window(art: PosterShape.landscape, fallback: PosterShape.portrait, window: PosterShape.portrait), PosterShape.portrait)
    XCTAssertEqual(PosterShape.window(art: nil, fallback: PosterShape.portrait, window: PosterShape.portrait), PosterShape.portrait)
  }

  func testWithoutAWindowTheArtShapesTheBox() {
    XCTAssertEqual(PosterShape.window(art: PosterShape.landscape, fallback: PosterShape.portrait, window: nil), PosterShape.landscape)
  }

  func testWithoutAWindowOrArtTheStandInShapesTheBox() {
    XCTAssertEqual(PosterShape.window(art: nil, fallback: PosterShape.portrait, window: nil), PosterShape.portrait)
  }

  func testAnUnusableWindowFallsBackToTheArt() {
    XCTAssertEqual(PosterShape.window(art: PosterShape.landscape, fallback: PosterShape.portrait, window: 0), PosterShape.landscape)
    XCTAssertEqual(PosterShape.window(art: PosterShape.landscape, fallback: PosterShape.portrait, window: .nan), PosterShape.landscape)
  }

  func testATallerPosterFillsTheWindowAndBleedsDownwards() {
    let box = CGSize(width: 231, height: 346.5)
    let taller = CGFloat(500) / 1000
    let draw = PosterShape.fill(size: box, art: taller)
    XCTAssertEqual(draw.width, 231, accuracy: 0.01)
    XCTAssertEqual(draw.height, 462, accuracy: 0.01)
    XCTAssertGreaterThan(draw.height, box.height)
  }

  func testAWiderStillFillsTheWindowAndBleedsSideways() {
    let box = CGSize(width: 231, height: 346.5)
    let draw = PosterShape.fill(size: box, art: PosterShape.landscape)
    XCTAssertEqual(draw.width, 616, accuracy: 0.5)
    XCTAssertEqual(draw.height, 346.5, accuracy: 0.01)
    XCTAssertGreaterThan(draw.width, box.width)
  }

  func testArtThatAlreadyMatchesTheWindowIsDrawnAsItIs() {
    let box = CGSize(width: 180, height: 285)
    let draw = PosterShape.fill(size: box, art: 180.0 / 285.0)
    XCTAssertEqual(draw.width, box.width, accuracy: 0.01)
    XCTAssertEqual(draw.height, box.height, accuracy: 0.01)
  }

  func testASizeThatCannotBeFilledIsLeftAlone() {
    let box = CGSize(width: 180, height: 100)
    XCTAssertEqual(PosterShape.fill(size: box, art: 0), box)
    XCTAssertEqual(PosterShape.fill(size: .zero, art: PosterShape.portrait), .zero)
  }
}
