import XCTest
@testable import SkillCappedLocal

final class LibraryScannerTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("skc-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
    root = nil
  }

  private func touch(_ relative: String, bytes: Int = 0) throws {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: bytes).write(to: url)
  }

  func testGroupsLessonsIntoTheirCourseFolder() throws {
    try touch("Courses/adc/Why You Suck at ADC (ADC)/What's Next [j413lhtmz7] 1080p.mp4")
    try touch("Courses/adc/Why You Suck at ADC (ADC)/Farming [a1b2c3d4e5] 1080p.mp4")

    let scan = LibraryScanner.scan(root: root)

    XCTAssertEqual(scan.courses.count, 1)
    let course = try XCTUnwrap(scan.courses.first)
    XCTAssertEqual(course.title, "Why You Suck at ADC (ADC)")
    XCTAssertEqual(course.role, "adc")
    XCTAssertEqual(course.lessons.count, 2)
    XCTAssertEqual(scan.lessonCount, 2)
    XCTAssertTrue(scan.videos.isEmpty)
  }

  func testCatalogueNamesLessonsAndDecidesTheirOrder() throws {
    try touch("Courses/adc/Course One/First [aaaaaa1111] 1080p.mp4")
    try touch("Courses/adc/Course One/Second [bbbbbb2222] 1080p.mp4")

    let json = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"course1","kind":"course","title":"Course One","role":"adc","lessonIds":["bbbbbb2222","aaaaaa1111"]},
      {"id":"aaaaaa1111","kind":"video","title":"First Lesson","role":"adc","durationSec":600,"courseTitle":"Course One"},
      {"id":"bbbbbb2222","kind":"video","title":"Second Lesson","role":"adc","durationSec":900,"courseTitle":"Course One"}
    ]}
    """
    let catalog = try XCTUnwrap(CatalogIndex.decode(Data(json.utf8)))
    let scan = LibraryScanner.scan(root: root, catalog: catalog)

    let course = try XCTUnwrap(scan.courses.first)
    XCTAssertEqual(course.title, "Course One")
    XCTAssertEqual(course.lessons.map(\.title), ["Second Lesson", "First Lesson"])
    XCTAssertEqual(course.lessons.first?.seconds, 900)
  }

  func testLooseVideosAndCommentariesStaySeparate() throws {
    try touch("Videos/mid/Ahri vs Zed [c3d4e5f6a7] 1080p.mp4")
    try touch("Commentaries/jungle/Coaching Session [d4e5f6a7b8] 1080p.mp4")

    let scan = LibraryScanner.scan(root: root)

    XCTAssertTrue(scan.courses.isEmpty)
    XCTAssertEqual(scan.videos.count, 1)
    XCTAssertEqual(scan.videos.first?.role, "mid")
    XCTAssertEqual(scan.commentaries.count, 1)
    XCTAssertEqual(scan.commentaries.first?.role, "jungle")
  }

  func testIgnoresStateFilesUnplayableMediaAndPlainFiles() throws {
    try touch(".skillcapped/catalog.json")
    try touch(".skillcapped/jobs.json")
    try touch("Videos/mid/Cancelled [ffffffff] 1080p.ts")
    try touch("Videos/mid/notes.txt")

    let scan = LibraryScanner.scan(root: root)

    XCTAssertTrue(scan.isEmpty)
  }

  func testKeepsAVideoCopiedInByHand() throws {
    try touch("Videos/adc/Random lesson.mp4")

    let scan = LibraryScanner.scan(root: root)

    XCTAssertEqual(scan.videos.count, 1)
    XCTAssertEqual(scan.videos.first?.title, "Random lesson")
    XCTAssertNil(scan.videos.first?.itemId)
  }

  func testALessonStillInICloudIsListedAtTheNameItRestoresTo() throws {
    try touch("Courses/adc/Course One/.Farming [a1b2c3d4e5] 1080p.mp4.icloud", bytes: 24)

    let scan = LibraryScanner.scan(root: root)

    let course = try XCTUnwrap(scan.courses.first)
    XCTAssertEqual(course.title, "Course One")
    let lesson = try XCTUnwrap(course.lessons.first)
    XCTAssertEqual(lesson.title, "Farming")
    XCTAssertEqual(lesson.quality, "1080p")
    XCTAssertEqual(lesson.url.lastPathComponent, "Farming [a1b2c3d4e5] 1080p.mp4")
    XCTAssertTrue(lesson.needsDownload, "a placeholder has no bytes to play")
    XCTAssertEqual(lesson.bytes, 0, "the shadow file's size is not the lesson's")
  }

  func testAPlaceholderBesideItsDownloadedCopyAppearsOnce() throws {
    try touch("Videos/adc/Ahri vs Zed [c3d4e5f6a7] 1080p.mp4", bytes: 900)
    try touch("Videos/adc/.Ahri vs Zed [c3d4e5f6a7] 1080p.mp4.icloud", bytes: 24)

    let scan = LibraryScanner.scan(root: root)

    XCTAssertEqual(scan.videos.count, 1)
    XCTAssertEqual(scan.videos.first?.bytes, 900)
  }

  func testSumsTheBytesOnDisk() throws {
    try touch("Courses/adc/Course One/One [aaaaaa1111] 1080p.mp4", bytes: 1000)
    try touch("Videos/adc/Two [bbbbbb2222] 1080p.mp4", bytes: 24)

    let scan = LibraryScanner.scan(root: root)

    XCTAssertEqual(scan.totalBytes, 1024)
  }

  func testCatalogueDecodeToleratesMissingFields() throws {
    let json = #"{"items":[{"id":"x","kind":"video","title":"Bare"}]}"#
    let catalog = try XCTUnwrap(CatalogIndex.decode(Data(json.utf8)))
    XCTAssertEqual(catalog.item("x")?.title, "Bare")
    XCTAssertEqual(catalog.item("x")?.durationSec, 0)
    XCTAssertNil(catalog.generatedAt)
  }

  func testEmptyCatalogueFailsClosed() {
    XCTAssertNil(CatalogIndex.decode(Data("{}".utf8)))
    XCTAssertNil(CatalogIndex.decode(Data("not json".utf8)))
  }
}
