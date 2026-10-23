import XCTest
@testable import SkillCappedLocal

/// What a picked folder is decided before the main actor sees it, because the
/// reading is the part that can wait on a file provider. These pin the answers,
/// the count of folders read, and that a huge tree stops instead of crawling.
final class LibraryPickTests: XCTestCase {
  private var scratch: URL!
  private let manager = FileManager.default

  override func setUpWithError() throws {
    scratch = manager.temporaryDirectory
      .appendingPathComponent("skc-pick-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? manager.removeItem(at: scratch)
    scratch = nil
  }

  private var documents: URL {
    manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  @discardableResult
  private func lesson(_ relative: String, in root: URL? = nil) throws -> URL {
    let file = (root ?? scratch).appendingPathComponent(relative)
    try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 3, count: 32).write(to: file)
    return file
  }

  private func library(named name: String) throws -> URL {
    let root = scratch.appendingPathComponent(name, isDirectory: true)
    try lesson("Courses/adc/Course One/Lesson [a1b2c3d4e5] 1080p.mp4", in: root)
    return root
  }

  func testTheLibraryItselfIsTakenAsItself() throws {
    let lib = try library(named: "SkillCapped")

    let pick = LibraryPick.prepare(lib, documents: documents)

    XCTAssertEqual(pick.target.standardizedFileURL.path, lib.standardizedFileURL.path)
    XCTAssertFalse(pick.ownFolder)
    XCTAssertFalse(pick.insideDocuments)
    XCTAssertNotNil(pick.bookmark, "a folder outside Documents is remembered as a bookmark")
    XCTAssertEqual(pick.visited, 1, "a folder that is already a library is not searched further")
    XCTAssertNil(pick.problem)
  }

  func testTheLibraryInsideThePickIsAdopted() throws {
    let lib = try library(named: "SkillCapped")
    try manager.createDirectory(
      at: scratch.appendingPathComponent("Photos", isDirectory: true),
      withIntermediateDirectories: true
    )

    let pick = LibraryPick.prepare(scratch, documents: documents)

    XCTAssertEqual(pick.target.standardizedFileURL.path, lib.standardizedFileURL.path)
    XCTAssertGreaterThan(pick.visited, 1)
    XCTAssertFalse(pick.capped)
  }

  func testAFolderHoldingTwoLibrariesIsTakenAsGiven() throws {
    try lesson("One/Courses/adc/A/Lesson [a1b2c3d4e5] 1080p.mp4")
    try lesson("Two/Courses/adc/B/Lesson [a1b2c3d4e5] 1080p.mp4")

    let pick = LibraryPick.prepare(scratch, documents: documents)

    XCTAssertEqual(
      pick.target.standardizedFileURL.path,
      scratch.standardizedFileURL.path,
      "two libraries are nobody's guess to make"
    )
  }

  func testAnEmptyFolderIsTakenAsGiven() throws {
    let pick = LibraryPick.prepare(scratch, documents: documents)

    XCTAssertEqual(pick.target.standardizedFileURL.path, scratch.standardizedFileURL.path)
    XCTAssertEqual(pick.visited, 1)
    XCTAssertTrue(pick.summary.contains("1 folder read"))
  }

  func testTheAppsOwnFolderNeedsNoSearchAndNoBookmark() throws {
    let pick = LibraryPick.prepare(documents, documents: documents)

    XCTAssertTrue(pick.ownFolder)
    XCTAssertEqual(pick.target.standardizedFileURL.path, documents.standardizedFileURL.path)
    XCTAssertNil(pick.bookmark)
    XCTAssertEqual(pick.visited, 0, "the app's own folder is never searched")
    XCTAssertFalse(pick.scopeStarted, "the sandbox already grants it")
  }

  func testAFolderInsideDocumentsIsReadWithoutABookmark() throws {
    let inside = documents.appendingPathComponent("skc-inside-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: inside, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: inside) }

    let pick = LibraryPick.prepare(inside, documents: documents)

    XCTAssertTrue(pick.insideDocuments)
    XCTAssertNil(pick.bookmark)
    XCTAssertEqual(pick.target.standardizedFileURL.path, inside.standardizedFileURL.path)
  }

  func testAHugeTreeStopsEarlyAndSaysSo() throws {
    for index in 0..<(LibraryLocator.walkBudget + 10) {
      try manager.createDirectory(
        at: scratch.appendingPathComponent("bulk/\(index)", isDirectory: true),
        withIntermediateDirectories: true
      )
    }

    let pick = LibraryPick.prepare(scratch, documents: documents)

    XCTAssertTrue(pick.capped)
    XCTAssertEqual(pick.visited, LibraryLocator.walkBudget)
    XCTAssertEqual(pick.target.standardizedFileURL.path, scratch.standardizedFileURL.path)
    XCTAssertTrue(pick.summary.contains("stopped early"))
  }

  func testThePickReportsHowLongItTook() throws {
    let pick = LibraryPick.prepare(try library(named: "SkillCapped"), documents: documents)

    XCTAssertGreaterThanOrEqual(pick.milliseconds, 0)
    XCTAssertTrue(pick.summary.contains("ms"))
  }
}
