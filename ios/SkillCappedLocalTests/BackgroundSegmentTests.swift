import XCTest

@testable import SkillCappedLocal

final class BackgroundSegmentTests: XCTestCase {
  func testAPartKnowsWhereItGoesAfterARelaunch() throws {
    let folder = URL(fileURLWithPath: "/tmp/scratch/j413lhtmz7", isDirectory: true)
    let part = BackgroundSegment(uuid: "j413lhtmz7", jobFolder: folder, index: 7)

    let encoded = try XCTUnwrap(part.encoded)
    let decoded = try XCTUnwrap(BackgroundSegment.decode(encoded))

    XCTAssertEqual(decoded, part)
    XCTAssertEqual(decoded.uuid, "j413lhtmz7")
    XCTAssertEqual(decoded.index, 7)
    XCTAssertEqual(decoded.jobFolder, folder.path)
  }

  func testThePartLandsWhereTheDownloaderLooksForIt() {
    let folder = URL(fileURLWithPath: "/tmp/scratch/j413lhtmz7", isDirectory: true)
    let part = BackgroundSegment(uuid: "j413lhtmz7", jobFolder: folder, index: 42)

    XCTAssertEqual(part.partURL, SegmentDownloader.partURL(folder, 42))
    XCTAssertEqual(part.partURL.lastPathComponent, "00042.ts")
  }

  func testATaskDescriptionThatIsNotAPartIsIgnored() {
    XCTAssertNil(BackgroundSegment.decode(nil))
    XCTAssertNil(BackgroundSegment.decode(""))
    XCTAssertNil(BackgroundSegment.decode("not json at all"))
  }
}
