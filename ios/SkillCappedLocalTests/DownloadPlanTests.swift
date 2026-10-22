import XCTest
@testable import SkillCappedLocal

final class DownloadPlanTests: XCTestCase {
  private func shape(
    kind: String = "video",
    title: String = "Farming",
    role: String = "adc",
    category: String = "Fundamentals",
    courseTitle: String? = nil
  ) -> DownloadShape {
    DownloadShape(kind: kind, title: title, role: role, category: category, courseTitle: courseTitle)
  }

  func testCourseVideoLandsInsideItsCourse() {
    let folder = DownloadPlan.folder(for: shape(courseTitle: "Why You Suck (ADC)"))
    XCTAssertEqual(folder, ["Courses", "adc", "Why You Suck (ADC)"])
  }

  func testLooseVideoLandsInItsCategory() {
    XCTAssertEqual(DownloadPlan.folder(for: shape()), ["Videos", "adc", "Fundamentals"])
  }

  func testLooseVideoWithoutACategoryStillLandsSomewhere() {
    XCTAssertEqual(DownloadPlan.folder(for: shape(category: "")), ["Videos", "adc", "General"])
  }

  func testCommentaryLandsBesideItsRole() {
    XCTAssertEqual(
      DownloadPlan.folder(for: shape(kind: "commentary", category: "")),
      ["Commentaries", "adc"]
    )
  }

  func testMissingRoleFallsBackToAll() {
    XCTAssertEqual(DownloadPlan.folder(for: shape(role: "", category: "")), ["Videos", "all", "General"])
  }

  func testFileNameCarriesTheIdAndQuality() {
    let name = DownloadPlan.fileName(title: "Farming", id: "j413lhtmz7", qualityLabel: "1080p")
    XCTAssertEqual(name, "Farming [j413lhtmz7] 1080p.mp4")
  }

  func testSanitizeStripsWhatWindowsRefuses() {
    XCTAssertEqual(DownloadPlan.sanitize("Wave: Control / Farming?"), "Wave Control Farming")
  }

  func testSanitizeKeepsUnicode() {
    XCTAssertEqual(DownloadPlan.sanitize("Pokeémon — ünïcode"), "Pokeémon — ünïcode")
  }

  func testSanitizeDropsTrailingDotsAndSpaces() {
    XCTAssertEqual(DownloadPlan.sanitize("Wave Control... "), "Wave Control")
  }

  func testSanitizeEscapesAReservedDeviceName() {
    XCTAssertEqual(DownloadPlan.sanitize("con"), "con_")
    XCTAssertEqual(DownloadPlan.sanitize("LPT1"), "LPT1_")
  }

  func testSanitizeNeverReturnsAnEmptyComponent() {
    XCTAssertEqual(DownloadPlan.sanitize("   "), "untitled")
    XCTAssertEqual(DownloadPlan.sanitize("///"), "untitled")
  }

  func testSanitizeTrimsToTheBudget() {
    let long = String(repeating: "a", count: 400)
    XCTAssertEqual(DownloadPlan.sanitize(long).count, 90)
  }

  func testLongTitleKeepsTheSuffixIntact() {
    let name = DownloadPlan.fileName(
      title: String(repeating: "a", count: 400),
      id: "j413lhtmz7",
      qualityLabel: "1080p"
    )
    XCTAssertTrue(name.hasSuffix(" [j413lhtmz7] 1080p.mp4"))
    XCTAssertLessThanOrEqual(name.count, 90)
  }

  func testDestinationIsNestedUnderTheRoot() {
    // The folder is the course, the file name is the lesson — the desktop's
    // destinationPath builds them the same way, so the two libraries merge.
    let url = DownloadPlan.destination(
      root: URL(fileURLWithPath: "/lib"),
      shape: shape(courseTitle: "Wave Control"),
      id: "abc123",
      qualityLabel: "720p"
    )
    XCTAssertEqual(url.path, "/lib/Courses/adc/Wave Control/Farming [abc123] 720p.mp4")
  }


  func testExpectedSegmentsRoundsUp() {
    XCTAssertEqual(DownloadPlan.expectedSegments(durationSec: 0), 1)
    XCTAssertEqual(DownloadPlan.expectedSegments(durationSec: 10), 1)
    XCTAssertEqual(DownloadPlan.expectedSegments(durationSec: 11), 2)
    XCTAssertEqual(DownloadPlan.expectedSegments(durationSec: 3_600), 360)
  }
}
