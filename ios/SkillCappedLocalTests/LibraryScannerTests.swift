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

  /// A lesson downloaded on the phone has no frame to show — iOS cannot decode a
  /// transport stream — so the poster the catalogue prints is what the card draws.
  func testCataloguePostersFollowTheirLessonAndCourse() throws {
    try touch("Courses/adc/Course One/First [aaaaaa1111] 1080p.ts")

    let json = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"course1","kind":"course","title":"Course One","role":"adc",
       "thumb":"https://cdn.example/course.jpg","lessonIds":["aaaaaa1111"]},
      {"id":"aaaaaa1111","kind":"video","title":"First Lesson","role":"adc",
       "thumb":"https://cdn.example/lesson.jpg","durationSec":600,"courseTitle":"Course One"}
    ]}
    """
    let catalog = try XCTUnwrap(CatalogIndex.decode(Data(json.utf8)))
    let scan = LibraryScanner.scan(root: root, catalog: catalog)

    let course = try XCTUnwrap(scan.courses.first)
    let lesson = try XCTUnwrap(course.lessons.first)
    XCTAssertEqual(lesson.posterURL?.absoluteString, "https://cdn.example/lesson.jpg")
    XCTAssertEqual(course.posterURL?.absoluteString, "https://cdn.example/course.jpg")
    XCTAssertEqual(course.artURL, course.posterURL, "the printed poster is preferred to a frame")
  }

  func testAThumbThatIsNotAnAddressIsNotDrawn() throws {
    try touch("Videos/mid/Ahri vs Zed [c3d4e5f6a7] 1080p.mp4")

    let json = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"c3d4e5f6a7","kind":"video","title":"Ahri vs Zed","thumb":"thumb.jpg"}
    ]}
    """
    let catalog = try XCTUnwrap(CatalogIndex.decode(Data(json.utf8)))
    let scan = LibraryScanner.scan(root: root, catalog: catalog)

    let video = try XCTUnwrap(scan.videos.first)
    XCTAssertNil(video.posterURL, "a bare path would be read as a file the app never wrote")
  }

  /// A folder the phone filled itself carries no `.skillcapped/catalog.json` —
  /// that is a desktop artefact — so the fetched catalogue is what gives such a
  /// library its titles, order and posters.
  func testAFetchedCatalogueNamesAPhoneOnlyLibrary() throws {
    try touch("Courses/adc/Course One/First [aaaaaa1111] 1080p.ts")
    try touch("Courses/adc/Course One/Second [bbbbbb2222] 1080p.ts")

    let fetched = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"course1","kind":"course","title":"Course One","role":"adc",
       "thumb":"https://cdn.example/course.jpg","lessonIds":["bbbbbb2222","aaaaaa1111"]},
      {"id":"aaaaaa1111","kind":"video","title":"First Lesson","durationSec":600},
      {"id":"bbbbbb2222","kind":"video","title":"Second Lesson","durationSec":900}
    ]}
    """
    let catalog = CatalogIndex.merged(
      primary: CatalogIndex.load(root: root) ?? .empty,
      secondary: try XCTUnwrap(CatalogIndex.decode(Data(fetched.utf8)))
    )
    let scan = LibraryScanner.scan(root: root, catalog: catalog)

    let course = try XCTUnwrap(scan.courses.first)
    XCTAssertEqual(course.lessons.map(\.title), ["Second Lesson", "First Lesson"])
    XCTAssertEqual(course.lessons.first?.seconds, 900)
    XCTAssertNotNil(course.posterURL)
  }

  func testTheLibrarysOwnCatalogueWinsWhereTheTwoDisagree() throws {
    try touch("Courses/adc/Course One/First [aaaaaa1111] 1080p.ts")

    let local = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"aaaaaa1111","kind":"video","title":"Named On Disk","durationSec":42}
    ]}
    """
    let fetched = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"aaaaaa1111","kind":"video","title":"Named Upstream","durationSec":600}
    ]}
    """
    let merged = CatalogIndex.merged(
      primary: try XCTUnwrap(CatalogIndex.decode(Data(local.utf8))),
      secondary: try XCTUnwrap(CatalogIndex.decode(Data(fetched.utf8)))
    )

    XCTAssertEqual(merged.item("aaaaaa1111")?.title, "Named On Disk")
    XCTAssertEqual(merged.item("aaaaaa1111")?.durationSec, 42)
  }

  /// The desktop's own catalog.json and the site can name different courses for
  /// one lesson id. Keying a course on a catalogue id split its folder into two
  /// cards with the same title; the folder on disk is the course.
  func testAFolderStaysOneCardWhenTwoCatalogueCoursesClaimItsLessons() throws {
    try touch("Courses/adc/Why You Suck at ADC (ADC)/What's Next [j413lhtmz7] 1080p.mp4")
    try touch("Courses/adc/Why You Suck at ADC (ADC)/Farming [a1b2c3d4e5] 1080p.mp4")

    let catalog = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"local1","kind":"course","title":"Why You Suck at ADC (ADC)","role":"adc","lessonIds":["a1b2c3d4e5"]},
      {"id":"site99","kind":"course","title":"Why You Suck at ADC (ADC)","role":"adc","lessonIds":["j413lhtmz7"]},
      {"id":"a1b2c3d4e5","kind":"video","title":"Farming","durationSec":905,"courseTitle":"Why You Suck at ADC (ADC)"},
      {"id":"j413lhtmz7","kind":"video","title":"What's Next","durationSec":842,"courseTitle":"Why You Suck at ADC (ADC)"}
    ]}
    """

    let scan = LibraryScanner.scan(root: root, catalog: try XCTUnwrap(CatalogIndex.decode(Data(catalog.utf8))))

    XCTAssertEqual(scan.courses.count, 1, "one folder is one course")
    let course = try XCTUnwrap(scan.courses.first)
    XCTAssertEqual(course.title, "Why You Suck at ADC (ADC)")
    XCTAssertEqual(course.lessons.count, 2)
  }

  /// The catalogue the app fetches arrives after the first scan, so a course
  /// that changed its key on arrival would drop the card the user was looking at.
  func testACoursesIdentitySurvivesTheCatalogueArriving() throws {
    try touch("Courses/adc/Course One/First [aaaaaa1111] 1080p.mp4")

    let catalog = """
    {"generatedAt": 1700000000000, "items": [
      {"id":"course1","kind":"course","title":"Course One","role":"adc","lessonIds":["aaaaaa1111"]},
      {"id":"aaaaaa1111","kind":"video","title":"First Lesson","durationSec":600}
    ]}
    """

    let bare = try XCTUnwrap(LibraryScanner.scan(root: root).courses.first)
    let named = try XCTUnwrap(
      LibraryScanner.scan(root: root, catalog: try XCTUnwrap(CatalogIndex.decode(Data(catalog.utf8)))).courses.first
    )

    XCTAssertEqual(bare.id, named.id)
    XCTAssertEqual(bare.title, "Course One")
    XCTAssertEqual(named.title, "Course One")
  }

  func testLooseVideosAndCommentariesStaySeparate() throws {    try touch("Videos/mid/Ahri vs Zed [c3d4e5f6a7] 1080p.mp4")
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
    try touch("Videos/mid/Cancelled [ffffffff] 1080p.mkv")
    try touch("Videos/mid/notes.txt")

    let scan = LibraryScanner.scan(root: root)

    XCTAssertTrue(scan.isEmpty)
  }

  func testATransportStreamDownloadedOnThePhoneIsALesson() throws {
    try touch("Videos/mid/Ahri vs Zed [c3d4e5f6a7] 1080p.ts")

    let scan = LibraryScanner.scan(root: root)

    XCTAssertEqual(scan.videos.count, 1)
    XCTAssertEqual(scan.videos.first?.itemId, "c3d4e5f6a7")
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
