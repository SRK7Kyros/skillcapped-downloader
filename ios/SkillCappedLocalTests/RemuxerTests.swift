import AVFoundation
import XCTest

@testable import SkillCappedLocal

final class RemuxerTests: XCTestCase {
  private func fixture() throws -> URL {
    try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "lesson", withExtension: "ts"),
      "the test bundle is missing Fixtures/lesson.ts"
    )
  }

  func testTransportStreamIsReadable() async throws {
    let asset = AVURLAsset(url: try fixture())
    let video = (try? await asset.loadTracks(withMediaType: .video)) ?? []
    let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
    XCTAssertFalse(
      video.isEmpty,
      "AVFoundation cannot demux this transport stream (video \(video.count), audio \(audio.count))"
    )
    XCTAssertFalse(audio.isEmpty, "the fixture's audio track is missing")
  }

  func testRemuxWritesAPlayableMp4() async throws {
    let output = FileManager.default.temporaryDirectory
      .appendingPathComponent("remux-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: output) }

    try await Remuxer.remux(ts: try fixture(), to: output)
    try await Remuxer.verify(output, expectedSeconds: 3)

    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 3, accuracy: 1)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    XCTAssertEqual(audio.count, 1, "the remux dropped the audio track")
  }

  func testVerifyRejectsAnEmptyFile() async throws {
    let empty = FileManager.default.temporaryDirectory
      .appendingPathComponent("empty-\(UUID().uuidString).mp4")
    XCTAssertTrue(FileManager.default.createFile(atPath: empty.path, contents: Data()))
    defer { try? FileManager.default.removeItem(at: empty) }

    do {
      try await Remuxer.verify(empty, expectedSeconds: 30)
      XCTFail("a zero-byte file must not pass verification")
    } catch {
      // Any failure is the pass: the file has nothing in it.
    }
  }
}
