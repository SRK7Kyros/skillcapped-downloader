import AVFoundation
import XCTest
@testable import SkillCappedLocal

final class VideoFitTests: XCTestCase {
  func testFitLetterboxesAndFillCrops() {
    XCTAssertEqual(VideoFit.fit.gravity, .resizeAspect, "fit keeps the whole frame")
    XCTAssertEqual(VideoFit.fill.gravity, .resizeAspectFill, "fill crops what does not fit")
  }

  func testTheToggleSwapsTheTwo() {
    XCTAssertEqual(VideoFit.fit.toggled, .fill)
    XCTAssertEqual(VideoFit.fill.toggled, .fit)
    XCTAssertEqual(VideoFit.fit.toggled.toggled, .fit, "two taps come back")
  }

  func testTheLabelNamesTheActionRatherThanTheState() {
    XCTAssertEqual(VideoFit.fit.actionLabel, "Fill the screen", "letterboxed, so the button can fill")
    XCTAssertEqual(VideoFit.fill.actionLabel, "Fit the whole video", "cropped, so the button can zoom out")
  }

  func testEachStateDrawsItsOwnGlyph() {
    XCTAssertNotEqual(VideoFit.fit.glyph, VideoFit.fill.glyph)
    XCTAssertEqual(Set(VideoFit.allCases.map(\.glyph)).count, VideoFit.allCases.count)
  }

  func testASavedPreferenceReadsBackAsTheSameChoice() throws {
    for fit in VideoFit.allCases {
      let data = try JSONEncoder().encode(fit)
      XCTAssertEqual(try JSONDecoder().decode(VideoFit.self, from: data), fit)
    }
  }
}
