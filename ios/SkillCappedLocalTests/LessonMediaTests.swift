import AVFoundation
import XCTest

@testable import SkillCappedLocal

final class LessonMediaTests: XCTestCase {
  private func fixture() throws -> URL {
    try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "lesson", withExtension: "ts"),
      "the test bundle is missing Fixtures/lesson.ts"
    )
  }

  func testAnOtherContainerIsHandedToThePlayerUntouched() throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("plain-\(UUID().uuidString).mp4")
    XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data([0])))
    defer { try? FileManager.default.removeItem(at: file) }

    let media = LessonMedia.item(url: file, seconds: 60)
    XCTAssertNil(media.loader)
    let url = (media.item.asset as? AVURLAsset)?.url
    XCTAssertEqual(url?.standardizedFileURL.path, file.standardizedFileURL.path)
  }

  func testThePlaylistStatesTheDurationAndEndsTheStream() {
    let loader = StreamAsset(file: URL(fileURLWithPath: "/tmp/x.ts"), seconds: 754)
    let playlist = loader.playlist
    XCTAssertTrue(playlist.hasPrefix("#EXTM3U"))
    XCTAssertTrue(playlist.contains("#EXT-X-TARGETDURATION:754"))
    XCTAssertTrue(playlist.contains("#EXTINF:754.000,"))
    XCTAssertTrue(playlist.contains("segment.ts"))
    XCTAssertTrue(playlist.contains("#EXT-X-ENDLIST"))
  }

  func testAnUnknownDurationStillProducesAPlayablePlaylist() {
    let loader = StreamAsset(file: URL(fileURLWithPath: "/tmp/x.ts"), seconds: 0)
    XCTAssertTrue(loader.playlist.contains("#EXTINF:\(StreamAsset.unknownSeconds).000,"))
    XCTAssertTrue(loader.playlist.contains("#EXT-X-ENDLIST"))
  }

  func testOnlyTransportStreamsGoThroughTheLoader() {
    XCTAssertTrue(StreamAsset.handles(URL(fileURLWithPath: "/a/B.ts")))
    XCTAssertTrue(StreamAsset.handles(URL(fileURLWithPath: "/a/B.TS")))
    XCTAssertFalse(StreamAsset.handles(URL(fileURLWithPath: "/a/B.mp4")))
  }

  /// The proof that a downloaded lesson can play at all. iOS has no MPEG-TS
  /// demuxer, so this duration only answers if the HLS stack accepted the
  /// loader's playlist and read the bytes it served from disk.
  func testTheLoaderMakesATransportStreamReadable() async throws {
    let media = LessonMedia.item(url: try fixture(), seconds: 3)
    XCTAssertNotNil(media.loader)

    let duration = try await media.item.asset.load(.duration)
    XCTAssertEqual(duration.seconds, 3, accuracy: 1)

    let audio = try await media.item.asset.loadTracks(withMediaType: .audio)
    XCTAssertEqual(audio.count, 1, "the loader served a stream without its audio track")
  }

  func testAPosterFrameComesOutOfATransportStream() async throws {
    let media = try XCTUnwrap(LessonMedia.assets(url: try fixture(), seconds: 3))
    let generator = AVAssetImageGenerator(asset: media.asset)
    let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
    XCTAssertGreaterThan(frame.image.width, 0)
  }
}
