import XCTest
@testable import SkillCappedLocal

/// The app's own folder is a library before anything is downloaded: Files shows
/// the three buckets, so it is obvious where a lesson lands.
final class LibraryBootstrapTests: XCTestCase {
  private var scratch: URL!

  override func setUpWithError() throws {
    scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("skc-bootstrap-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: scratch)
    scratch = nil
  }

  func testTheBucketsFilesShowsAreCreated() throws {
    LibraryBootstrap.createBuckets(in: scratch)

    let names = try FileManager.default.contentsOfDirectory(atPath: scratch.path).sorted()
    XCTAssertEqual(names, ["Commentaries", "Courses", "Videos"])
  }

  func testRunningItAgainKeepsWhatIsAlreadyThere() throws {
    let lesson = scratch
      .appendingPathComponent("Courses/adc/Course One", isDirectory: true)
      .appendingPathComponent("Farming [a1b2c3d4e5] 1080p.ts")
    try FileManager.default.createDirectory(at: lesson.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([0x47, 0x40, 0x11]).write(to: lesson)

    LibraryBootstrap.createBuckets(in: scratch)

    XCTAssertEqual(try Data(contentsOf: lesson), Data([0x47, 0x40, 0x11]))
  }

  func testEveryBucketIsOneTheLocatorLooksFor() {
    XCTAssertEqual(
      LibraryBootstrap.buckets.map { $0.lowercased() },
      LibraryLocator.buckets,
      "a bucket the app creates but the scanner does not look for would be invisible"
    )
  }

  /// The own folder is adopted by identity, not by content — which is exactly why
  /// `LibraryStore` must adopt it instead of searching for a library inside it.
  func testFreshBucketsAreNotYetALibrary() {
    LibraryBootstrap.createBuckets(in: scratch)

    XCTAssertFalse(LibraryLocator.isLibrary(scratch))
    XCTAssertTrue(LibraryLocator.libraries(in: scratch).isEmpty)
  }
}
