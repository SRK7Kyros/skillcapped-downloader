import XCTest
@testable import SkillCappedLocal

final class LibraryLocatorTests: XCTestCase {
  private var root: URL!
  private let manager = FileManager.default

  override func setUpWithError() throws {
    root = manager.temporaryDirectory.appendingPathComponent("locator-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? manager.removeItem(at: root)
  }

  private func touch(_ relative: String) throws {
    let url = root.appendingPathComponent(relative)
    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    _ = manager.createFile(atPath: url.path, contents: Data())
  }

  private func folder(_ relative: String) throws -> URL {
    let url = root.appendingPathComponent(relative, isDirectory: true)
    try manager.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func testAFolderHoldingALessonIsALibrary() throws {
    try touch("Courses/adc/Why You Suck at ADC/What's Next [j413lhtmz7] 1080p.mp4")
    XCTAssertTrue(LibraryLocator.isLibrary(root))
  }

  func testEachBucketCountsOnItsOwn() throws {
    for bucket in LibraryLocator.buckets {
      let solo = try folder("only-\(bucket)")
      try touch("only-\(bucket)/\(bucket)/anything.mp4")
      XCTAssertTrue(LibraryLocator.isLibrary(solo), "\(bucket) should be a library")
    }
  }

  func testAnUnrelatedFolderIsNotALibrary() throws {
    try touch("Screenshots/shot.png")
    XCTAssertFalse(LibraryLocator.isLibrary(root))
  }

  func testAnEmptyBucketFolderIsNotALibrary() throws {
    _ = try folder("Courses")
    XCTAssertFalse(LibraryLocator.isLibrary(root), "an empty Courses folder has nothing to read")
  }

  func testNestedLibrariesAreFoundOnce() throws {
    _ = try folder("downloads/holiday")
    try touch("SkillCapped/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")
    try touch("other/Archive/Commentaries/jungle/session [c3d4e5f6a7] 1080p.mp4")

    let found = LibraryLocator.libraries(in: root).map(\.lastPathComponent)
    XCTAssertEqual(found.count, 2)
    XCTAssertEqual(Set(found), ["SkillCapped", "Archive"])
  }

  func testFoundLibrariesKeepTheirRelativePaths() throws {
    try touch("SkillCapped/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")
    try touch("Archive/Commentaries/jungle/session [c3d4e5f6a7] 1080p.mp4")

    let paths = LibraryLocator.libraries(in: root)
      .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
      .sorted()
    XCTAssertEqual(paths, ["Archive", "SkillCapped"])
  }

  func testALibraryIsNotSearchedFurther() throws {
    try touch("SkillCapped/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")
    try touch("SkillCapped/nested/Courses/adc/course/other [b2c3d4e5f6] 1080p.mp4")

    let found = LibraryLocator.libraries(in: root)
    XCTAssertEqual(found.map(\.lastPathComponent), ["SkillCapped"])
  }

  func testHiddenFoldersAreSkipped() throws {
    try touch(".Trash/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")
    XCTAssertTrue(LibraryLocator.libraries(in: root).isEmpty)
  }

  func testSearchStopsBelowTheDepthLimit() throws {
    var deep = "SkillCapped"
    for index in 0..<(LibraryLocator.maxDepth + 2) {
      deep += "/level\(index)"
    }
    try touch("\(deep)/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")
    XCTAssertTrue(LibraryLocator.libraries(in: root).isEmpty)
  }

  func testAPickedFolderFindsTheLibraryInsideIt() throws {
    let picked = try folder("picked")
    try touch("picked/SkillCapped/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")

    let found = LibraryLocator.libraries(in: picked, depth: 2)
    XCTAssertEqual(found.map(\.lastPathComponent), ["SkillCapped"])
  }

  func testThePickedFolderLookStaysShallow() throws {
    let picked = try folder("picked")
    try touch("picked/a/b/c/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")

    XCTAssertTrue(LibraryLocator.libraries(in: picked, depth: 2).isEmpty)
    XCTAssertEqual(LibraryLocator.libraries(in: picked).map(\.lastPathComponent), ["c"])
  }

  func testThePickedFolderLookFindsTwoLevelsIn() throws {
    let picked = try folder("picked")
    try touch("picked/a/b/Courses/adc/course/lesson [a1b2c3d4e5] 1080p.mp4")

    XCTAssertEqual(LibraryLocator.libraries(in: picked, depth: 2).map(\.lastPathComponent), ["b"])
  }
}
