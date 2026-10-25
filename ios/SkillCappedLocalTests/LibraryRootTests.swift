import XCTest
@testable import SkillCappedLocal

final class LibraryRootTests: XCTestCase {
  private var suite = ""
  private var defaults: UserDefaults!
  private var documents: URL!

  override func setUpWithError() throws {
    suite = "skc-root-\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    documents = FileManager.default.temporaryDirectory
      .appendingPathComponent("skc-docs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suite)
    defaults = nil
    try? FileManager.default.removeItem(at: documents)
    documents = nil
  }

  private func folder(_ name: String) throws -> URL {
    let url = documents.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func bookmark(_ url: URL) throws -> Data {
    try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  private func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.resolvingSymlinksInPath().standardizedFileURL.path
      == rhs.resolvingSymlinksInPath().standardizedFileURL.path
  }

  func testNothingSavedIsTheAppsOwnFolder() throws {
    let root = try XCTUnwrap(LibraryRoot.resolve(defaults: defaults, documents: documents))

    XCTAssertTrue(samePath(root.url, documents))
    XCTAssertFalse(root.scoped)
  }

  func testAnEmptyPathIsTheAppsOwnFolder() throws {
    defaults.set("", forKey: LibraryRoot.pathKey)

    let root = try XCTUnwrap(LibraryRoot.resolve(defaults: defaults, documents: documents))

    XCTAssertTrue(samePath(root.url, documents))
  }

  func testARelativePathResolvesInsideDocuments() throws {
    let library = try folder("Lib")
    defaults.set("Lib", forKey: LibraryRoot.pathKey)

    let root = try XCTUnwrap(LibraryRoot.resolve(defaults: defaults, documents: documents))

    XCTAssertTrue(samePath(root.url, library))
    XCTAssertFalse(root.scoped)
  }

  /// A folder that moved or was deleted answers nothing at all: falling back to the
  /// app's own folder would write the lesson somewhere the user does not look.
  func testAPathThatIsNoLongerThereAnswersNothing() throws {
    defaults.set("Gone", forKey: LibraryRoot.pathKey)

    XCTAssertNil(LibraryRoot.resolve(defaults: defaults, documents: documents))
  }

  func testABookmarkResolvesToItsFolder() throws {
    let library = try folder("Picked")
    defaults.set(try bookmark(library), forKey: LibraryRoot.bookmarkKey)

    let root = try XCTUnwrap(LibraryRoot.resolve(defaults: defaults, documents: documents))
    defer { root.stop() }

    XCTAssertTrue(samePath(root.url, library))
  }

  func testABookmarkWhoseFolderIsGoneAnswersNothing() throws {
    let library = try folder("Vanished")
    defaults.set(try bookmark(library), forKey: LibraryRoot.bookmarkKey)
    try FileManager.default.removeItem(at: library)

    XCTAssertNil(LibraryRoot.resolve(defaults: defaults, documents: documents))
  }

  /// `LibraryStore.restore()` asks for the relative path first, so a stale one must
  /// not be answered by a bookmark that a later pick left behind.
  func testThePathDecidesBeforeABookmark() throws {
    let inside = try folder("Inside")
    let outside = try folder("Outside")
    defaults.set("Inside", forKey: LibraryRoot.pathKey)
    defaults.set(try bookmark(outside), forKey: LibraryRoot.bookmarkKey)

    let root = try XCTUnwrap(LibraryRoot.resolve(defaults: defaults, documents: documents))
    defer { root.stop() }

    XCTAssertTrue(samePath(root.url, inside))
  }
}
