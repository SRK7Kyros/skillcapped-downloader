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
  ///
  /// There is no audio track to count: an HLS variant is one muxed program, not
  /// a pair of tracks, so the transport stream reaching the demuxer whole is
  /// what makes its audio playable too.
  func testTheLoaderMakesATransportStreamReadable() async throws {
    let file = try fixture()
    let media = LessonMedia.item(url: file, seconds: 3)
    let loader = try XCTUnwrap(media.loader)

    let ready = await waitForReady(media.item)
    XCTAssertTrue(ready, "the player item never became ready; loader saw: \(loader.requests())")

    let duration = try await media.item.asset.load(.duration)
    XCTAssertEqual(duration.seconds, 3, accuracy: 1)

    let video = try await media.item.asset.loadTracks(withMediaType: .video)
    XCTAssertEqual(video.count, 1, "the loader served a stream without video; loader saw: \(loader.requests())")

    let size = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
    )
    XCTAssertTrue(
      loader.requests().contains("<- \(size)/\(size)"),
      "the player never read the whole transport stream (\(size) bytes); loader saw: \(loader.requests())"
    )
  }

  private func waitForReady(_ item: AVPlayerItem, seconds: Double = 20) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      switch item.status {
      case .readyToPlay: return true
      case .failed: return false
      case .unknown: try? await Task.sleep(nanoseconds: 100_000_000)
      @unknown default: return false
      }
    }
    return false
  }

  func testAPosterFrameComesOutOfATransportStream() async throws {
    let media = try XCTUnwrap(LessonMedia.assets(url: try fixture(), seconds: 3))
    let generator = AVAssetImageGenerator(asset: media.asset)
    let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
    XCTAssertGreaterThan(frame.image.width, 0)
  }
}
