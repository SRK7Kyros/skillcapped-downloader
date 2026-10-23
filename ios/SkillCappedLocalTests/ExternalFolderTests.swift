import XCTest
@testable import SkillCappedLocal

/// What the folder picker hands back, without a picker: a folder outside the
/// app's own Documents (remembered as a bookmark) and a folder that merely
/// *contains* the library (iCloud Drive's root), which is what the picker
/// returns when the user picks iCloud Drive itself.
@MainActor
final class ExternalFolderTests: XCTestCase {
  private var scratch: URL!

  override func setUpWithError() throws {
    scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("skc-external-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    LibraryStore().forget()
    try? FileManager.default.removeItem(at: scratch)
    scratch = nil
  }

  @discardableResult
  private func library(named name: String, into parent: URL) throws -> URL {
    let root = parent.appendingPathComponent(name, isDirectory: true)
    let lesson = root
      .appendingPathComponent("Courses/adc/Course One", isDirectory: true)
      .appendingPathComponent("Farming [a1b2c3d4e5] 1080p.mp4")
    try FileManager.default.createDirectory(at: lesson.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 9, count: 64).write(to: lesson)
    return root
  }

  private func waitForScan(_ store: LibraryStore, timeout: TimeInterval = 20) async throws -> LibraryScan {
    let deadline = Date().addingTimeInterval(timeout)
    while store.scan == nil, Date() < deadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    return try XCTUnwrap(store.scan, "the scan should finish")
  }

  private func waitForPick(_ store: LibraryStore, timeout: TimeInterval = 20) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while store.preparing != nil, Date() < deadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertNil(store.preparing, "the pick should finish")
  }

  func testAPickedFolderOutsideTheAppIsScannedAndRemembered() async throws {
    let picked = try library(named: "SkillCapped", into: scratch)
    let store = LibraryStore()

    store.choose(picked)
    try await waitForPick(store)

    XCTAssertTrue(store.hasFolder)
    XCTAssertEqual(store.rootName, "SkillCapped")
    let scan = try await waitForScan(store)
    XCTAssertEqual(scan.lessonCount, 1)
    XCTAssertEqual(scan.courses.first?.title, "Course One")

    let reopened = LibraryStore()
    XCTAssertEqual(reopened.rootName, "SkillCapped", "the bookmark should survive a relaunch")
    let rescanned = try await waitForScan(reopened)
    XCTAssertEqual(rescanned.lessonCount, 1)
  }

  func testPickingAFolderThatOnlyContainsTheLibraryAdoptsTheLibrary() async throws {
    try library(named: "SkillCapped", into: scratch)
    try FileManager.default.createDirectory(
      at: scratch.appendingPathComponent("Unrelated", isDirectory: true),
      withIntermediateDirectories: true
    )
    let store = LibraryStore()

    store.choose(scratch)
    try await waitForPick(store)

    XCTAssertEqual(store.rootName, "SkillCapped", "the library inside the pick is the library")
    let scan = try await waitForScan(store)
    XCTAssertEqual(scan.lessonCount, 1)
  }
}
