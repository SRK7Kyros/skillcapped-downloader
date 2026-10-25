import XCTest
@testable import SkillCappedLocal

final class DisplayCornerTests: XCTestCase {
  func testTheRadiiAMeasuredDisplayIsKnown() {
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 402, height: 874)), 62, "iPhone 17 Pro")
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 874, height: 402)), 62, "…on its side")
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 390, height: 844)), 47.33, "iPhone 14")
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 430, height: 932)), 55, "iPhone 15 Plus")
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 440, height: 956)), 62, "iPhone 17 Pro Max")
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 375, height: 812)), 44, "iPhone 13 mini")
  }

  func testAPadHasTheTighterCornerItHas() {
    for size in [CGSize(width: 744, height: 1133), CGSize(width: 834, height: 1194)] {
      XCTAssertEqual(DisplayCorner.radius(for: size), 18)
    }
  }

  func testSquareGlassRoundsNothing() {
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 375, height: 667)), 0, "the SE's rectangle")
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 667, height: 375)), 0)
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 320, height: 568)), 0)
  }

  func testADisplayNobodyMeasuredTakesTheShapeOfItsEra() {
    XCTAssertEqual(
      DisplayCorner.radius(for: CGSize(width: 460, height: 1010)),
      62,
      "a phone rounds about a seventh of its width, capped at what a hand holds"
    )
    XCTAssertEqual(DisplayCorner.radius(for: CGSize(width: 1000, height: 1400)), 18)
    XCTAssertEqual(DisplayCorner.radius(for: .zero), 0, "an unreadable display has no corner to place against")
  }

  func testTheGlassPullsItsFullRadiusInAtTheEdgeItself() {
    XCTAssertEqual(DisplayCorner.pull(radius: 55, distance: 0), 55)
    XCTAssertEqual(DisplayCorner.pull(radius: 55, distance: -10), 55, "past the edge is still the edge")
  }

  func testTheGlassStopsPullingWhereTheCurveEnds() {
    XCTAssertEqual(DisplayCorner.pull(radius: 55, distance: 55), 0)
    XCTAssertEqual(DisplayCorner.pull(radius: 55, distance: 200), 0)
    XCTAssertEqual(DisplayCorner.pull(radius: 0, distance: 0), 0)
  }

  func testThePullFallsAwayFromTheCorner() {
    let samples = [0, 5, 10, 20, 35, 50, 55].map { DisplayCorner.pull(radius: 55, distance: CGFloat($0)) }
    XCTAssertEqual(samples, samples.sorted(by: >), "closer to the corner is always more")
  }

  func testAContinuousCornerHugsItsEdgeMoreTightlyThanACircle() {
    // At half the radius in, a circle has already swallowed a fifth of it; an
    // Apple display corner has barely moved, which is the whole reason a control
    // can live in the corner at all.
    let half = DisplayCorner.pull(radius: 62, distance: 31)
    XCTAssertLessThan(half, 1)
    XCTAssertGreaterThan(half, 0)
    XCTAssertLessThan(
      half,
      62 - (62 * 62 - 31 * 31).squareRoot(),
      "a circle of the same radius would still be a third of the way out"
    )
  }

  func testTheDiagonalIsWhereTheCurveComesClosest() {
    let radius: CGFloat = 62
    let clearance = DisplayCorner.clearance(radius: radius)
    XCTAssertEqual(clearance, 8.03, accuracy: 0.1, "about an eighth of the radius, not a third")
    XCTAssertTrue(
      DisplayCorner.isInside(x: clearance + 0.5, y: clearance + 0.5, radius: radius),
      "a box at the diagonal clearance is on the glass, not off it"
    )
    XCTAssertFalse(
      DisplayCorner.isInside(x: clearance - 1, y: clearance - 1, radius: radius),
      "a point inside that is through it"
    )
  }

  func testTheMiddleOfAnEdgeIsAlwaysOnTheGlass() {
    XCTAssertTrue(DisplayCorner.isInside(x: 400, y: 0, radius: 62))
    XCTAssertTrue(DisplayCorner.isInside(x: 62, y: 62, radius: 62))
    XCTAssertFalse(DisplayCorner.isInside(x: -1, y: 0, radius: 62), "off the display")
    XCTAssertTrue(DisplayCorner.isInside(x: -1, y: 0, radius: 0), "square glass has no curve to be outside of")
  }
}
