import XCTest
@testable import SkillCappedLocal

final class DownloadNameTests: XCTestCase {
  func testParsesTheDownloaderSuffix() {
    let name = DownloadName.parse("What's Next [j413lhtmz7] 1080p.mp4")
    XCTAssertEqual(name.title, "What's Next")
    XCTAssertEqual(name.id, "j413lhtmz7")
    XCTAssertEqual(name.quality, "1080p")
  }

  func testKeepsPlainNamesWhole() {
    let name = DownloadName.parse("Random lesson.mp4")
    XCTAssertEqual(name.title, "Random lesson")
    XCTAssertNil(name.id)
    XCTAssertNil(name.number)
    XCTAssertNil(name.quality)
  }

  func testParsesANumberedName() {
    let name = DownloadName.parse("02 - What's Next 1080p.ts")
    XCTAssertEqual(name.title, "What's Next")
    XCTAssertEqual(name.number, 2)
    XCTAssertNil(name.id)
    XCTAssertEqual(name.quality, "1080p")
  }

  func testALegacyNameWinsOverTheNumberedShape() {
    let name = DownloadName.parse("3 - Wave Control [abcdef123] 1080p.mp4")
    XCTAssertEqual(name.id, "abcdef123")
    XCTAssertNil(name.number)
    XCTAssertEqual(name.quality, "1080p")
  }

  func testTheLastQualityTokenNamesTheFile() {
    let name = DownloadName.parse("3 - 1440p Settings Worth Changing 1080p.mp4")
    XCTAssertEqual(name.title, "1440p Settings Worth Changing")
    XCTAssertEqual(name.number, 3)
    XCTAssertEqual(name.quality, "1080p")
  }

  func testIgnoresAnUnknownQuality() {
    let name = DownloadName.parse("Lesson [abcdef123] streaming.mp4")
    XCTAssertEqual(name.title, "Lesson [abcdef123] streaming")
    XCTAssertNil(name.id)
  }

  func testTrimsTheTitle() {
    let name = DownloadName.parse("  Farming  [a1b2c3d4e5] 720p.mp4")
    XCTAssertEqual(name.title, "Farming")
    XCTAssertEqual(name.quality, "720p")
  }

  func testPlayableExtensions() {
    XCTAssertTrue(DownloadName.playableExtensions.contains("mp4"))
    XCTAssertTrue(DownloadName.playableExtensions.contains("ts"))
    XCTAssertFalse(DownloadName.playableExtensions.contains("json"))
  }
}
