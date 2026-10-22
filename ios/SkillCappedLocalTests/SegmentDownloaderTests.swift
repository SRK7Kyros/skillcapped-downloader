import XCTest

@testable import SkillCappedLocal

final class SegmentDownloaderTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("downloader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func touch(_ name: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data("x".utf8).write(to: url)
    return url
  }

  func testAnOldRenditionOfTheSameLessonGoes() throws {
    let stale = try touch("Farming [abc123] 720p.mp4")
    let fresh = try touch("Farming [abc123] 720p.ts")

    SegmentDownloader.discardStaleSiblings(of: fresh)

    XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
  }

  func testOtherLessonsAndOtherQualitiesStay() throws {
    let other = try touch("Farming [def456] 720p.ts")
    let higher = try touch("Farming [abc123] 1080p.mp4")
    let fresh = try touch("Farming [abc123] 720p.ts")

    SegmentDownloader.discardStaleSiblings(of: fresh)

    XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: higher.path))
  }
}
