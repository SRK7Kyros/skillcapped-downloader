import XCTest
@testable import SkillCappedLocal

/// The app's own folder — `Files › On My iPhone › SkillCapped Local` — is the
/// library unless another one is picked, so the app is never pointed at nothing
/// (and never at a hidden container path).
@MainActor
final class OwnFolderTests: XCTestCase {
  override func setUp() {
    UserDefaults.standard.removeObject(forKey: "library.bookmark")
    UserDefaults.standard.removeObject(forKey: "library.relativePath")
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: "library.bookmark")
    UserDefaults.standard.removeObject(forKey: "library.relativePath")
  }

  func testAFreshAppReadsItsOwnFolder() {
    let store = LibraryStore()

    XCTAssertEqual(
      store.libraryURL.standardizedFileURL.path,
      store.documentsURL.standardizedFileURL.path,
      "with nothing picked, the library is the folder Files shows"
    )
    XCTAssertEqual(store.downloadRoot.standardizedFileURL.path, store.documentsURL.standardizedFileURL.path)
    XCTAssertEqual(store.rootName, "SkillCapped Local")
    XCTAssertEqual(store.filesLocation, FilesPlace.ownFolder)
    XCTAssertTrue(store.usingOwnFolder)
    XCTAssertFalse(store.hasFolder, "the own folder is not a pick, so there is nothing to go back from")
  }

  func testTheOwnFolderIsReadyToReceiveLessons() {
    let store = LibraryStore()

    for bucket in LibraryBootstrap.buckets {
      var isDirectory: ObjCBool = false
      let path = store.documentsURL.appendingPathComponent(bucket, isDirectory: true).path
      XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory))
      XCTAssertTrue(isDirectory.boolValue, "\(bucket) should be a folder Files can open")
    }
  }

  func testAskingForTheOwnFolderKeepsItAsItIs() {
    let store = LibraryStore()

    store.choose(store.documentsURL)

    XCTAssertTrue(store.usingOwnFolder)
    XCTAssertFalse(store.hasFolder)
    XCTAssertEqual(store.rootName, "SkillCapped Local")
  }

  func testGoingBackLeavesTheOwnFolderInPlace() {
    let store = LibraryStore()

    store.forget()

    XCTAssertEqual(store.libraryURL.standardizedFileURL.path, store.documentsURL.standardizedFileURL.path)
    XCTAssertEqual(store.rootName, "SkillCapped Local")
    XCTAssertTrue(store.usingOwnFolder)
  }
}
