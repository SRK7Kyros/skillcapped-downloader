import XCTest
@testable import SkillCappedLocal

/// A downloaded file is named `<NN> - <Title> <quality>` and no longer carries an
/// id, so the number both surfaces print has to come out the same and the phone
/// has to be able to read a name it wrote back into the lesson it is.
final class CatalogNumberingTests: XCTestCase {
  private func item(
    _ id: String,
    title: String,
    kind: String = "video",
    role: String = "adc",
    category: String = "General",
    courseTitle: String? = nil,
    lessonIds: [String] = [],
    date: Double = 1_000
  ) -> CatalogItem {
    CatalogItem(
      id: id,
      kind: kind,
      title: title,
      role: role,
      durationSec: 60,
      date: Date(timeIntervalSince1970: date),
      category: category,
      courseTitle: courseTitle,
      lessonIds: lessonIds
    )
  }

  private func index(_ items: [CatalogItem]) -> CatalogIndex {
    CatalogIndex(items: items, generatedAt: nil)
  }

  func testACoursesLessonsTakeTheCoursesOwnOrder() {
    let catalog = index([
      item("b", title: "Second", date: 3_000),
      item("course", title: "Wave Control", kind: "course", lessonIds: ["c", "a", "b"]),
      item("a", title: "First", date: 5_000),
      item("c", title: "Third", date: 1_000),
    ])

    XCTAssertEqual(catalog.fileNumber(for: "c"), FileNumber(index: 1, total: 3))
    XCTAssertEqual(catalog.fileNumber(for: "a"), FileNumber(index: 2, total: 3))
    XCTAssertEqual(catalog.fileNumber(for: "b"), FileNumber(index: 3, total: 3))
    XCTAssertNil(catalog.fileNumber(for: "course"), "a course is a folder, not a numbered lesson")
  }

  func testLooseVideosInOneFolderAreNumberedNewestFirst() {
    let catalog = index([
      item("old", title: "Older", date: 1_000),
      item("new", title: "Newer", date: 5_000),
      item("mid", title: "Middle", date: 3_000),
    ])

    XCTAssertEqual(catalog.fileNumber(for: "new"), FileNumber(index: 1, total: 3))
    XCTAssertEqual(catalog.fileNumber(for: "mid"), FileNumber(index: 2, total: 3))
    XCTAssertEqual(catalog.fileNumber(for: "old"), FileNumber(index: 3, total: 3))
  }

  func testVideosInDifferentFoldersAreNumberedApart() {
    let catalog = index([
      item("a", title: "One", category: "General"),
      item("b", title: "Two", category: "Matchups"),
    ])

    XCTAssertEqual(catalog.fileNumber(for: "a"), FileNumber(index: 1, total: 1))
    XCTAssertEqual(catalog.fileNumber(for: "b"), FileNumber(index: 1, total: 1))
  }

  func testALessonACourseDoesNotListTakesNoNumber() {
    let catalog = index([
      item("course", title: "Wave Control", kind: "course", lessonIds: ["a"]),
      item("a", title: "First", courseTitle: "Wave Control"),
      item("stray", title: "Stray", courseTitle: "Wave Control"),
    ])

    XCTAssertEqual(catalog.fileNumber(for: "a"), FileNumber(index: 1, total: 1))
    XCTAssertNil(catalog.fileNumber(for: "stray"), "the course owns its folder and its numbering")
  }

  func testTheCollectionSizeIsWhatTheNumberIsPaddedTo() {
    let lessons = (1...12).map { item("l\($0)", title: "Lesson \($0)") }
    let catalog = index([item("course", title: "Wave Control", kind: "course", lessonIds: lessons.map(\.id))] + lessons)

    XCTAssertEqual(catalog.fileNumber(for: "l2"), FileNumber(index: 2, total: 12))
    XCTAssertEqual(DownloadPlan.numberPrefix(catalog.fileNumber(for: "l2")), "02 - ")
    XCTAssertEqual(DownloadPlan.numberPrefix(FileNumber(index: 2, total: 9)), "2 - ")
  }

  func testLocateReadsANumberedNameBackIntoItsLesson() {
    let catalog = index([item("abc", title: "Farming")])
    let folder = DownloadPlan.folder(for: CatalogIndex.shape(of: item("abc", title: "Farming")))
      .joined(separator: "/")
    let written = DownloadPlan.fileName(
      title: "Farming",
      number: catalog.fileNumber(for: "abc"),
      qualityLabel: "1080p",
      extension: "ts"
    )

    let parsed = DownloadName.parse(written)
    XCTAssertNil(parsed.id, "a numbered name carries no id")
    XCTAssertEqual(parsed.number, 1)
    XCTAssertEqual(catalog.locate(folder: folder, title: parsed.title)?.id, "abc")
  }

  func testLocateAcceptsATitleTruncatedToFitThePathBudget() {
    let title = "Chapter 3: The Very Long Lesson Title That Keeps On Going And On"
    let catalog = index([item("long", title: title)])
    let folder = DownloadPlan.folder(for: CatalogIndex.shape(of: item("long", title: title)))
      .joined(separator: "/")
    let written = DownloadPlan.fileName(
      title: title,
      number: FileNumber(index: 3, total: 9),
      qualityLabel: "1080p",
      maxLength: 34
    )
    let parsed = DownloadName.parse(written)

    XCTAssertLessThan(parsed.title.count, DownloadPlan.sanitize(title).count)
    XCTAssertEqual(catalog.locate(folder: folder, title: parsed.title)?.id, "long")
  }

  func testLocateIgnoresAStubTooShortToBeATitle() {
    let catalog = index([item("chapter", title: "Chapter 3: Crushing the Early Game")])

    XCTAssertNil(catalog.locate(folder: "Videos/adc/General", title: "Cha"))
  }

  func testLocateTakesTheShortestTitleAFragmentCouldHaveComeFrom() {
    let catalog = index([
      item("long", title: "Wave Control Advanced Laning Patterns"),
      item("short", title: "Wave Control Advanced"),
    ])

    XCTAssertEqual(catalog.locate(folder: "Videos/adc/General", title: "Wave Control Adv")?.id, "short")
  }

  func testLocateResolvesATitleTwoLessonsShareByIdOrder() {
    let catalog = index([
      item("zzz", title: "Farming"),
      item("aaa", title: "Farming"),
    ])

    XCTAssertEqual(catalog.locate(folder: "Videos/adc/General", title: "Farming")?.id, "aaa")
  }

  func testLocateKeepsAFolderToItsOwnLessons() {
    let catalog = index([
      item("a", title: "Farming", category: "General"),
      item("b", title: "Farming", category: "Matchups"),
    ])

    XCTAssertEqual(catalog.locate(folder: "Videos/adc/General", title: "Farming")?.id, "a")
    XCTAssertEqual(catalog.locate(folder: "Videos/adc/Matchups", title: "Farming")?.id, "b")
    XCTAssertNil(catalog.locate(folder: "Videos/adc/Nowhere", title: "Farming"))
  }
}
