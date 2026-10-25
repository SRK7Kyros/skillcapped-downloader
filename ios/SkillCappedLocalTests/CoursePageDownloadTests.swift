import XCTest
@testable import SkillCappedLocal

/// What a course page's download pill is allowed to disappear for.
///
/// The rule the page got wrong: the pill was drawn from "lessons nobody is
/// fetching", so a course whose download *failed* — a third of a course, on this
/// CDN — looked finished and had no way to ask for the rest. It is drawn from
/// "lessons this phone has not got" instead, and greys out while the queue holds
/// them, so starting a download never looks like finishing one.
final class CoursePageDownloadTests: XCTestCase {
  func testACourseWithLessonsMissingIsNotCompleteAndAsksForThem() {
    let rows = [row("a", .onDisk), row("b", .remote), row("c", .remote)]

    XCTAssertFalse(rows.isComplete)
    XCTAssertEqual(rows.missingItems.map(\.id), ["b", "c"])
  }

  func testAFailedLessonIsAskedForAgain() {
    let rows = [row("a", .onDisk), row("b", .failed("403")), row("c", .failed("403"))]

    XCTAssertFalse(rows.isComplete)
    XCTAssertEqual(rows.missingItems.map(\.id), ["b", "c"])
  }

  func testALessonTheQueueIsFetchingIsNotAskedForTwice() {
    let rows = [
      row("a", .onDisk),
      row("b", .queued),
      row("c", .downloading(0.4)),
      row("d", .remuxing),
    ]

    XCTAssertFalse(rows.isComplete)
    XCTAssertTrue(rows.missingItems.isEmpty)
  }

  func testOneLessonStillAskableForKeepsTheWholeCourseAskable() {
    let rows = [row("a", .onDisk), row("b", .queued), row("c", .failed("timeout"))]

    XCTAssertEqual(rows.missingItems.map(\.id), ["c"])
  }

  func testACompleteCourseAsksForNothing() {
    let rows = [row("a", .onDisk), row("b", .onDisk)]

    XCTAssertTrue(rows.isComplete)
    XCTAssertTrue(rows.missingItems.isEmpty)
  }

  func testACourseWithNoPublishedLessonsOffersNoDownload() {
    let rows: [CourseLesson] = []

    XCTAssertTrue(rows.isComplete)
    XCTAssertTrue(rows.missingItems.isEmpty)
  }

  private func row(_ id: String, _ state: RowState) -> CourseLesson {
    CourseLesson(
      id: id,
      title: "Lesson \(id)",
      index: 1,
      local: state == .onDisk ? lesson(id) : nil,
      still: nil,
      remote: nil,
      seconds: 120,
      bytes: state == .onDisk ? 1_000 : nil,
      quality: state == .onDisk ? "1080p" : nil,
      state: state,
      progress: nil,
      item: item(id),
      note: nil
    )
  }

  private func lesson(_ id: String) -> Lesson {
    Lesson(
      id: id,
      url: URL(fileURLWithPath: "/tmp/\(id).mp4"),
      title: "Lesson \(id)",
      role: "adc",
      quality: "1080p",
      seconds: 120,
      bytes: 1_000,
      modified: nil,
      itemId: id,
      needsDownload: false
    )
  }

  private func item(_ id: String) -> CatalogItem {
    CatalogItem(id: id, kind: "video", title: "Lesson \(id)", role: "adc", courseTitle: "Demo")
  }
}
