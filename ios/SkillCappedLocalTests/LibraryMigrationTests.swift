import XCTest
@testable import SkillCappedLocal

/// What "choose a folder" does with what is already on the phone: the library is
/// carried into the folder that was picked, merged where that folder already holds
/// a copy, and nothing the destination has is overwritten.
final class LibraryMigrationTests: XCTestCase {
  private var scratch: URL!

  override func setUpWithError() throws {
    scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("skc-move-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: scratch)
    scratch = nil
  }

  private func write(_ relative: String, in root: URL, bytes: Int = 64) throws -> URL {
    let url = root.appendingPathComponent(relative, isDirectory: false)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: bytes).write(to: url)
    return url
  }

  private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  private func size(of url: URL) -> Int? {
    (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
  }

  func testTheLessonsMoveIntoTheFolderThatWasPicked() throws {
    let source = scratch.appendingPathComponent("OnPhone", isDirectory: true)
    let destination = scratch.appendingPathComponent("iCloud/Library", isDirectory: true)
    let course = "Courses/adc/Course One/Farming [a1b2c3d4e5] 1080p.ts"
    let video = "Videos/mid/Laning/Episode [b2c3d4e5f6] 720p.ts"
    let lesson = try write(course, in: source)
    try write(video, in: source)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    let report = LibraryMigration.run(from: source, to: destination)

    XCTAssertEqual(report.moved, 2)
    XCTAssertEqual(report.merged, 0)
    XCTAssertEqual(report.bytes, 128)
    XCTAssertFalse(exists(lesson), "the lesson is carried, not copied")
    XCTAssertTrue(exists(destination.appendingPathComponent(course)))
    XCTAssertTrue(exists(destination.appendingPathComponent(video)))
    XCTAssertFalse(exists(source.appendingPathComponent("Courses")), "the folders the move emptied go with it")
  }

  func testAnExistingFileIsNotOverwritten() throws {
    let source = scratch.appendingPathComponent("OnPhone", isDirectory: true)
    let destination = scratch.appendingPathComponent("Library", isDirectory: true)
    let lesson = "Courses/adc/Course One/Farming [a1b2c3d4e5] 1080p.ts"
    try write(lesson, in: source)
    let there = try write(lesson, in: destination, bytes: 32)

    let report = LibraryMigration.run(from: source, to: destination)

    XCTAssertEqual(report.moved, 0)
    XCTAssertEqual(report.kept, [lesson], "the file the destination already has is named, not replaced")
    XCTAssertEqual(size(of: there), 32, "the destination keeps its own copy")
    XCTAssertTrue(exists(source.appendingPathComponent(lesson)), "the other copy stays where it was")
  }

  func testASecondCopyOfTheSameFileIsDroppedFromTheOldFolder() throws {
    let source = scratch.appendingPathComponent("OnPhone", isDirectory: true)
    let destination = scratch.appendingPathComponent("Library", isDirectory: true)
    let lesson = "Courses/adc/Course One/Farming [a1b2c3d4e5] 1080p.ts"
    try write(lesson, in: source)
    try write(lesson, in: destination)

    let report = LibraryMigration.run(from: source, to: destination)

    XCTAssertEqual(report.merged, 1)
    XCTAssertEqual(report.moved, 0)
    XCTAssertTrue(report.kept.isEmpty)
    XCTAssertFalse(exists(source.appendingPathComponent(lesson)))
    XCTAssertTrue(exists(destination.appendingPathComponent(lesson)))
  }

  func testOnlyTheLibraryIsCarried() throws {
    let source = scratch.appendingPathComponent("OnPhone", isDirectory: true)
    let destination = scratch.appendingPathComponent("Library", isDirectory: true)
    let photo = try write("Photos/holiday.jpg", in: source)
    let loose = try write("Laning Against [c3d4e5f6a7] 1080p.mp4", in: source)
    let note = try write("readme.txt", in: source)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    let report = LibraryMigration.run(from: source, to: destination)

    XCTAssertEqual(report.moved, 1)
    XCTAssertTrue(exists(photo), "a folder that is not the app's stays put")
    XCTAssertTrue(exists(note))
    XCTAssertFalse(exists(loose), "a lesson sitting at the top of the library is the app's")
    XCTAssertTrue(exists(destination.appendingPathComponent("Laning Against [c3d4e5f6a7] 1080p.mp4")))
  }

  func testTheCatalogueCacheTravelsWithTheFilesItNames() throws {
    let source = scratch.appendingPathComponent("OnPhone", isDirectory: true)
    let destination = scratch.appendingPathComponent("Library", isDirectory: true)
    let cache = try write(".skillcapped/catalog.json", in: source, bytes: 12)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    let report = LibraryMigration.run(from: source, to: destination)

    XCTAssertEqual(report.moved, 1)
    XCTAssertFalse(exists(cache))
    XCTAssertTrue(exists(destination.appendingPathComponent(".skillcapped/catalog.json")))
  }

  func testALessonStillInTheCloudIsNotFetchedToBeMoved() throws {
    let source = scratch.appendingPathComponent("OnPhone", isDirectory: true)
    let destination = scratch.appendingPathComponent("Library", isDirectory: true)
    let shadow = try write("Courses/adc/Course One/.Farming [a1b2c3d4e5] 1080p.mp4.icloud", in: source)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    let report = LibraryMigration.run(from: source, to: destination)

    XCTAssertEqual(report.moved, 0)
    XCTAssertTrue(exists(shadow))
  }

  func testAFolderIsNeverMovedIntoItselfOrItsOwnChild() {
    let root = scratch.appendingPathComponent("Library", isDirectory: true)
    let child = root.appendingPathComponent("Courses", isDirectory: true)
    let sibling = scratch.appendingPathComponent("Other", isDirectory: true)

    XCTAssertFalse(LibraryMigration.canMove(from: root, to: root))
    XCTAssertFalse(LibraryMigration.canMove(from: root, to: child))
    XCTAssertFalse(LibraryMigration.canMove(from: child, to: root))
    XCTAssertTrue(LibraryMigration.canMove(from: root, to: sibling))
  }

  func testARememberedPathFollowsItsFile() {
    let source = URL(fileURLWithPath: "/private/old")
    let destination = URL(fileURLWithPath: "/private/new")

    XCTAssertEqual(
      LibraryMigration.relocated("/private/old/Courses/adc/Course/A [id] 1080p.ts", from: source, to: destination),
      "/private/new/Courses/adc/Course/A [id] 1080p.ts"
    )
    XCTAssertNil(LibraryMigration.relocated("/private/elsewhere/A [id] 1080p.ts", from: source, to: destination))
  }

  func testProgressCountsTheFilesAsTheyLand() throws {
    let source = scratch.appendingPathComponent("OnPhone", isDirectory: true)
    let destination = scratch.appendingPathComponent("Library", isDirectory: true)
    try write("Courses/adc/Course One/One [a1b2c3d4e5] 1080p.ts", in: source)
    try write("Videos/mid/Laning/Two [b2c3d4e5f6] 720p.ts", in: source)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let seen = Box()

    _ = LibraryMigration.run(from: source, to: destination) { seen.values.append($0) }

    XCTAssertEqual(seen.values.first?.total, 2)
    XCTAssertEqual(seen.values.first?.waiting, false)
    XCTAssertEqual(seen.values.last?.done, 2)
    XCTAssertEqual(seen.values.last?.bytes, 128)
  }
}

private final class Box: @unchecked Sendable {
  var values: [LibraryMigration.Progress] = []
}
