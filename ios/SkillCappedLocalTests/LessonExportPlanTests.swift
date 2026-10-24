import XCTest

@testable import SkillCappedLocal

/// What *export* decides before a byte is read: the shape a lesson leaves in, the
/// name the sheet offers, and whether there is a file here to leave at all.
final class LessonExportPlanTests: XCTestCase {
  private func lesson(_ name: String, needsDownload: Bool = false) -> Lesson {
    Lesson(
      id: "j413lhtmz7",
      url: URL(fileURLWithPath: "/tmp/\(name)"),
      title: "Why You Suck at ADC",
      role: "ADC",
      quality: "1080p",
      seconds: 600,
      bytes: 300_000_000,
      modified: nil,
      itemId: "j413lhtmz7",
      needsDownload: needsDownload
    )
  }

  // MARK: - Shape

  /// A transport stream is exactly what this app writes and exactly what nothing
  /// else opens, so its extension is the whole decision.
  func testATransportStreamIsRepackagedAndEverythingElseIsNot() {
    XCTAssertEqual(LessonExportPlan.shape(for: URL(fileURLWithPath: "/a/x.ts")), .remux)
    XCTAssertEqual(LessonExportPlan.shape(for: URL(fileURLWithPath: "/a/x.TS")), .remux)
    XCTAssertEqual(LessonExportPlan.shape(for: URL(fileURLWithPath: "/a/x.mp4")), .asIs)
    XCTAssertEqual(LessonExportPlan.shape(for: URL(fileURLWithPath: "/a/x.merged.ts.part")), .asIs)
  }

  // MARK: - Name

  func testTheNameTheSheetOffersCarriesTheTitleAndItsQuality() {
    XCTAssertEqual(
      LessonExportPlan.fileName(title: "Why You Suck at ADC", quality: "1080p"),
      "Why You Suck at ADC 1080p.mp4"
    )
    XCTAssertEqual(
      LessonExportPlan.fileName(title: "Why You Suck at ADC", quality: nil),
      "Why You Suck at ADC.mp4",
      "a lesson with no stated quality gets no empty suffix"
    )
    XCTAssertEqual(
      LessonExportPlan.fileName(title: "Why You Suck at ADC", quality: "   "),
      "Why You Suck at ADC.mp4"
    )
  }

  /// The uuid the library files a lesson under is the library's business, not the
  /// person choosing where this goes — and a slash in a title cannot become a
  /// folder on the way out.
  func testTheNameIsSafeToWriteAnywhere() {
    let name = LessonExportPlan.fileName(title: "A/B: the \"real\" one?", quality: "4K")
    XCTAssertFalse(name.contains("/"))
    XCTAssertFalse(name.contains(":"))
    XCTAssertTrue(name.hasSuffix(" 4K.mp4"))
  }

  func testTheExportLandsInTheFolderItIsGiven() {
    let folder = URL(fileURLWithPath: "/tmp/exports", isDirectory: true)
    XCTAssertEqual(
      LessonExportPlan.destination(folder: folder, title: "Farming", quality: "720p").path,
      "/tmp/exports/Farming 720p.mp4"
    )
  }

  // MARK: - There has to be a file

  /// A lesson only in iCloud is a shadow file: neither a share sheet nor a delete
  /// has anywhere to say "fetching it first".
  func testALessonThatIsOnlyInTheCloudHasNothingToShareOrDelete() {
    XCTAssertTrue(LessonExportPlan.isOnThisPhone(lesson("here.ts")))
    XCTAssertFalse(LessonExportPlan.isOnThisPhone(lesson("away.mp4", needsDownload: true)))
  }

  // MARK: - A whole course

  func testACourseOfMP4sGoesStraightOut() {
    let plan = LessonExportPlan.batch([lesson("a.mp4"), lesson("b.mp4")])
    XCTAssertEqual(plan.lessons.count, 2)
    XCTAssertTrue(plan.converts.isEmpty)
    XCTAssertFalse(plan.asksFirst, "an MP4 already opens anywhere, so nothing is asked")
  }

  func testACourseConvertsOnlyItsTransportStreams() {
    let plan = LessonExportPlan.batch([lesson("a.ts"), lesson("b.mp4")])
    XCTAssertEqual(
      plan.lessons.map(\.url.lastPathComponent),
      ["a.ts", "b.mp4"],
      "the sheet keeps the order the course lists them in"
    )
    XCTAssertEqual(plan.converts.map(\.url.lastPathComponent), ["a.ts"])
    XCTAssertTrue(plan.asksFirst)
  }

  func testACourseWithNothingOnThisPhoneHasNothingToOffer() {
    let plan = LessonExportPlan.batch([lesson("a.ts", needsDownload: true)])
    XCTAssertTrue(plan.isEmpty)
    XCTAssertTrue(plan.converts.isEmpty)
  }

  func testACourseLeavesOutTheVideosThatAreOnlyInTheCloud() {
    let plan = LessonExportPlan.batch([lesson("here.mp4"), lesson("away.ts", needsDownload: true)])
    XCTAssertEqual(plan.lessons.map(\.url.lastPathComponent), ["here.mp4"])
    XCTAssertTrue(plan.converts.isEmpty, "a video that was dropped cannot force the question")
  }
}
