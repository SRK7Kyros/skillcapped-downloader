import CoreGraphics
import XCTest
@testable import SkillCappedLocal

final class CourseLayoutTests: XCTestCase {
  func testALandscapeWindowGetsTheColumns() {
    XCTAssertTrue(CourseLayout.isSideBySide(CGSize(width: 844, height: 390)))
    XCTAssertTrue(CourseLayout.isSideBySide(CGSize(width: 1_180, height: 820)))
  }

  func testAPortraitWindowStacks() {
    XCTAssertFalse(CourseLayout.isSideBySide(CGSize(width: 390, height: 844)))
    XCTAssertFalse(CourseLayout.isSideBySide(CGSize(width: 820, height: 1_180)))
  }

  func testASquareWindowStacks() {
    XCTAssertFalse(CourseLayout.isSideBySide(CGSize(width: 600, height: 600)))
  }

  func testAWindowThatDescribesNoScreenStacks() {
    XCTAssertFalse(CourseLayout.isSideBySide(.zero))
    XCTAssertFalse(CourseLayout.isSideBySide(CGSize(width: CGFloat.nan, height: 390)))
    XCTAssertFalse(CourseLayout.isSideBySide(CGSize(width: 844, height: CGFloat.infinity)))
  }

  func testThePosterColumnIsWhatTheArtNeedsToFillTheHeight() {
    let side = CourseLayout.posterColumn(size: CGSize(width: 844, height: 330), ratio: PosterShape.portrait)
    XCTAssertEqual(side, 330 * PosterShape.portrait, accuracy: 0.01)
    XCTAssertLessThan(side, 844 * CourseLayout.posterShare)
  }

  func testThePosterColumnIsCappedOnAWideWindow() {
    let size = CGSize(width: 1_180, height: 820)
    let side = CourseLayout.posterColumn(size: size, ratio: PosterShape.portrait)
    XCTAssertEqual(side, size.width * CourseLayout.posterShare, accuracy: 0.01)
    XCTAssertLessThan(side, size.height * PosterShape.portrait)
  }

  func testAPosterColumnNeedsARealWindowAndShape() {
    XCTAssertEqual(CourseLayout.posterColumn(size: .zero, ratio: PosterShape.portrait), 0)
    XCTAssertEqual(CourseLayout.posterColumn(size: CGSize(width: 844, height: 330), ratio: 0), 0)
    XCTAssertEqual(CourseLayout.posterColumn(size: CGSize(width: 844, height: 330), ratio: .nan), 0)
    XCTAssertEqual(CourseLayout.posterColumn(size: CGSize(width: 844, height: CGFloat.nan), ratio: PosterShape.portrait), 0)
  }

  func testTheStackedPosterIsAThirdOfTheWidth() {
    XCTAssertEqual(CourseLayout.heroWidth(for: 390), 390 * CourseLayout.heroShare, accuracy: 0.01)
    XCTAssertLessThan(CourseLayout.heroWidth(for: 390), 390 / 3)
  }

  func testTheStackedPosterNeverGrowsIntoThePage() {
    XCTAssertEqual(CourseLayout.heroWidth(for: 820), CourseLayout.heroCeiling)
    XCTAssertEqual(CourseLayout.heroWidth(for: 2_400), CourseLayout.heroCeiling)
  }

  func testTheStackedPosterKeepsAReadableFloor() {
    XCTAssertEqual(CourseLayout.heroWidth(for: 240), CourseLayout.heroFloor)
    XCTAssertEqual(CourseLayout.heroWidth(for: 0), CourseLayout.heroFloor)
    XCTAssertEqual(CourseLayout.heroWidth(for: .nan), CourseLayout.heroFloor)
  }

  func testAPosterNeverTakesHalfOfANarrowWindow() {
    XCTAssertLessThanOrEqual(CourseLayout.heroWidth(for: 200), 200 * 0.42 + 0.01)
    XCTAssertGreaterThan(CourseLayout.heroWidth(for: 200), 0)
  }

  func testTheRowsTurnCompactOnlyWhenTheLessonColumnIsNarrow() {
    XCTAssertFalse(CourseLayout.lessonsAreTight(width: 844, side: 236))
    XCTAssertTrue(CourseLayout.lessonsAreTight(width: 667, side: 236))
    XCTAssertTrue(CourseLayout.lessonsAreTight(width: 620, side: CourseLayout.posterColumn(
      size: CGSize(width: 620, height: 300),
      ratio: PosterShape.portrait
    )))
  }

  func testAWindowThatCannotMeasureIsNotTight() {
    XCTAssertFalse(CourseLayout.lessonsAreTight(width: .nan, side: 236))
    XCTAssertFalse(CourseLayout.lessonsAreTight(width: 844, side: .infinity))
  }
}
