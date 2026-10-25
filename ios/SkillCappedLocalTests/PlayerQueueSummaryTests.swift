import XCTest
@testable import SkillCappedLocal

final class PlayerQueueSummaryTests: XCTestCase {
  func testALessonNobodyHasStartedShowsItsLengthAlone() {
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: nil), "14:02")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: 0), "14:02")
  }

  func testProgressIsTheShareWatchedBesideTheLength() {
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: 0.42), "Watched 42% · 14:02")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 59, watched: 0.01), "Watched 1% · 0:59")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 3_725, watched: 0.5), "Watched 50% · 1:02:05")
  }

  func testTheLastSlicesReadAsWatchedRatherThanNinetyNinePercent() {
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: 1), "Watched · 14:02")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: 0.996), "Watched · 14:02")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: 0.99), "Watched 99% · 14:02")
  }

  func testAShareOutsideTheBarIsClampedOrIgnored() {
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: 1.4), "Watched · 14:02")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: -0.2), "14:02")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: .nan), "14:02")
    XCTAssertEqual(PlayerQueueSummary.detail(seconds: 842, watched: .infinity), "14:02")
  }

  func testAPositionNamesWhereTheLessonSits() throws {
    let queue = ["a", "b", "c"].map(lesson)
    XCTAssertEqual(PlayerQueueSummary.position(of: "a", in: queue), "1 of 3")
    XCTAssertEqual(PlayerQueueSummary.position(of: "c", in: queue), "3 of 3")
    XCTAssertNil(PlayerQueueSummary.position(of: "z", in: queue), "a lesson outside the list has no place in it")
  }

  func testAQueueOfOneNamesNoPosition() {
    let queue = ["a"].map(lesson)
    XCTAssertNil(PlayerQueueSummary.position(of: "a", in: queue))
    XCTAssertNil(PlayerQueueSummary.position(of: "a", in: []))
  }

  private func lesson(_ id: String) -> Lesson {
    Lesson(
      id: id,
      url: URL(fileURLWithPath: "/tmp/\(id).mp4"),
      title: "Lesson \(id)",
      role: "top",
      quality: "1080p",
      seconds: 600,
      bytes: 1_024,
      modified: nil,
      itemId: id,
      needsDownload: false
    )
  }
}
