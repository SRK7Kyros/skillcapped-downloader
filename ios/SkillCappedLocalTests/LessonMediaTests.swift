import AVFoundation
import UIKit
import XCTest

@testable import SkillCappedLocal

final class LessonMediaTests: XCTestCase {
  private func fixture() throws -> URL {
    try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "lesson", withExtension: "ts"),
      "the test bundle is missing Fixtures/lesson.ts"
    )
  }

  func testAnOtherContainerIsHandedToThePlayerUntouched() async throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("plain-\(UUID().uuidString).mp4")
    XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data([0])))
    defer { try? FileManager.default.removeItem(at: file) }

    let item = await LessonMedia.item(url: file, seconds: 60)

    let url = (item.asset as? AVURLAsset)?.url
    XCTAssertEqual(url?.standardizedFileURL.path, file.standardizedFileURL.path)
  }

  func testThePlaylistStatesTheDurationAndEndsTheStream() {
    let playlist = LessonServer.playlist(token: "abc", port: 8731, seconds: 754)
    XCTAssertTrue(playlist.hasPrefix("#EXTM3U"))
    XCTAssertTrue(playlist.contains("#EXT-X-TARGETDURATION:754"))
    XCTAssertTrue(playlist.contains("#EXTINF:754.000,"))
    XCTAssertTrue(playlist.contains("http://127.0.0.1:8731/lesson/abc/segment.ts"))
    XCTAssertTrue(playlist.contains("#EXT-X-ENDLIST"))
  }

  func testAnUnknownDurationStillProducesAPlayablePlaylist() {
    let playlist = LessonServer.playlist(token: "abc", port: 8731, seconds: 0)
    XCTAssertTrue(playlist.contains("#EXTINF:\(LessonServer.unknownSeconds).000,"))
    XCTAssertTrue(playlist.contains("#EXT-X-ENDLIST"))
  }

  func testOnlyTransportStreamsGoThroughTheServer() {
    XCTAssertTrue(LessonServer.offers(URL(fileURLWithPath: "/a/B.ts")))
    XCTAssertTrue(LessonServer.offers(URL(fileURLWithPath: "/a/B.TS")))
    XCTAssertFalse(LessonServer.offers(URL(fileURLWithPath: "/a/B.mp4")))
  }

  /// The server has to answer a playlist and a byte range before the player is
  /// involved at all, so its own contract is checked without AVFoundation.
  func testTheServerServesAPlaylistAndAByteRange() async throws {
    let file = try fixture()
    let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
    XCTAssertGreaterThan(size, 1024)

    let playlistURL = try await LessonServer.shared.url(for: file, seconds: 3)
    let (playlist, playlistResponse) = try await URLSession.shared.data(from: playlistURL)
    XCTAssertEqual((playlistResponse as? HTTPURLResponse)?.statusCode, 200)
    let text = try XCTUnwrap(String(data: playlist, encoding: .utf8))
    XCTAssertTrue(text.contains("#EXT-X-ENDLIST"))
    let segment = try XCTUnwrap(text.split(separator: "\n").first { $0.hasSuffix("segment.ts") })
    let segmentURL = try XCTUnwrap(URL(string: String(segment).trimmingCharacters(in: .whitespaces)))

    var request = URLRequest(url: segmentURL)
    request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
    let (bytes, segmentResponse) = try await URLSession.shared.data(for: request)
    let response = try XCTUnwrap(segmentResponse as? HTTPURLResponse)
    XCTAssertEqual(response.statusCode, 206)
    XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Range"), "bytes 0-1023/\(size)")
    XCTAssertEqual(bytes.count, 1024)
    XCTAssertEqual(bytes.first, UInt8(0x47), "a transport stream starts with its sync byte")

    let missing = try XCTUnwrap(URL(string: "http://127.0.0.1:\(playlistURL.port ?? 0)/lesson/nope/segment.ts"))
    let (_, gone) = try await URLSession.shared.data(from: missing)
    XCTAssertEqual((gone as? HTTPURLResponse)?.statusCode, 404)
  }

  /// The proof that a downloaded lesson can play at all. iOS has no MPEG-TS
  /// demuxer, so this only passes if the player read the playlist and decoded the
  /// bytes the server handed it: a bare transport stream reports no video size
  /// and its timeline never moves.
  func testATransportStreamPlaysThroughTheLocalServer() async throws {
    let item = await LessonMedia.item(url: try fixture(), seconds: 3)
    let player = AVPlayer(playerItem: item)
    player.play()

    let ready = await waitForReady(item)
    XCTAssertTrue(ready, "the player item never became ready (\(item.error.map { String(describing: $0) } ?? "no error"))")
    XCTAssertGreaterThan(item.presentationSize.width, 0, "the player read a stream without video")
    XCTAssertEqual(item.duration.seconds, 3, accuracy: 1)

    let started = player.currentTime().seconds
    try await Task.sleep(nanoseconds: 1_500_000_000)
    let advanced = player.currentTime().seconds - started
    player.pause()
    XCTAssertGreaterThan(advanced, 0.2, "playback did not advance (\(advanced)s)")
  }

  /// A transport stream can play and still yield no cover art: the player reads it
  /// as HLS, and an HLS asset reports no tracks for an image generator to decode.
  /// What matters is that the request settles at once instead of hanging a card.
  func testAPosterForATransportStreamIsNotWaitedOn() async throws {
    let started = Date()
    let poster = await PosterStore.shared.poster(for: try fixture(), width: 320)
    XCTAssertNil(poster, "an HLS asset reported a frame it has no tracks for")
    XCTAssertLessThan(Date().timeIntervalSince(started), 2, "a transport stream must not be waited on")
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
}
