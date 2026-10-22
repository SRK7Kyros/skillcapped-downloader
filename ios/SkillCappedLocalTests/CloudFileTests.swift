import XCTest
@testable import SkillCappedLocal

final class CloudFileTests: XCTestCase {
  func testOrdinaryFilesNeverNeedADownload() {
    XCTAssertFalse(CloudFile.needsDownload(isUbiquitous: nil, status: nil))
    XCTAssertFalse(CloudFile.needsDownload(isUbiquitous: false, status: .notDownloaded))
  }

  func testACurrentCloudFileIsAlreadyLocal() {
    XCTAssertFalse(CloudFile.needsDownload(isUbiquitous: true, status: .current))
  }

  func testAPlaceholderNeedsADownload() {
    XCTAssertTrue(CloudFile.needsDownload(isUbiquitous: true, status: .notDownloaded))
    XCTAssertTrue(CloudFile.needsDownload(isUbiquitous: true, status: nil))
  }

  func testAnOlderVersionStillCountsAsMissing() {
    XCTAssertTrue(CloudFile.needsDownload(isUbiquitous: true, status: .downloaded))
  }

  func testALocalFileIsReportedReady() async {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("local-\(UUID().uuidString).mp4")
    XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x47])))
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertFalse(CloudFile.needsDownload(url))
    let ready = await CloudFile.waitUntilLocal(url)
    XCTAssertTrue(ready)
  }
}
