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

  /// A transport stream is not asked for a frame at all: the card keeps its
  /// gradient rather than pay for a request that may never return. This pins the
  /// guard, not the platform — whether the asset could yield a frame is what
  /// `testTheHLSAssetReportsWhatItExposes` surveys.
  func testAPosterForATransportStreamIsNotWaitedOn() async throws {
    let started = Date()
    let poster = await PosterStore.shared.poster(for: try fixture(), width: 320)
    XCTAssertNil(poster, "a transport stream must not be asked for a frame")
    XCTAssertLessThan(Date().timeIntervalSince(started), 2, "a transport stream must not be waited on")
  }

  /// What the local server's HLS asset actually exposes.
  ///
  /// The app skips cover art for a transport stream on the grounds that an HLS
  /// asset reports no tracks. Nothing ever read that list: it was inferred from a
  /// poster request that never returned, and the asset here is an ordinary
  /// `http://127.0.0.1` m3u8 — the resource-loader route was rejected precisely
  /// because it reported a duration and never a frame — so the claim needs a
  /// direct answer before the guard is treated as a platform limit.
  ///
  /// The assertion is only that the survey settles: a load that never answers is
  /// the failure worth pinning, because waiting on one once truncated a whole test
  /// session. The finding is the printed `HLS_SURVEY` line, and the commit that
  /// acts on it turns the answer into an assertion.
  func testTheHLSAssetReportsWhatItExposes() async throws {
    let item = await LessonMedia.item(url: try fixture(), seconds: 3)
    let survey = await settle { await Self.survey(item) }
    print("HLS_SURVEY: " + (survey ?? "no answer within \(Self.surveyBudget)s"))
    XCTAssertNotNil(survey, "the HLS asset never answered what it exposes")
  }

  /// The survey itself, printed a fact at a time so a load that stalls still
  /// leaves everything it reached in the CI log before the deadline expires.
  private static func survey(_ item: AVPlayerItem) async -> String {
    var parts: [String] = []

    func record(_ name: String, _ value: String) {
      parts.append("\(name)=\(value)")
      print("HLS_SURVEY_STEP: \(name)=\(value)")
    }

    let asset = item.asset
    record("presentation", "\(Int(item.presentationSize.width))x\(Int(item.presentationSize.height))")
    record("playable", ((try? await asset.load(.isPlayable)) ?? nil).map(String.init) ?? "unknown")
    record(
      "duration",
      ((try? await asset.load(.duration)) ?? nil).map { String(format: "%.2fs", $0.seconds) } ?? "unknown"
    )

    guard let tracks = (try? await asset.load(.tracks)) ?? nil else {
      record("tracks", "unknown")
      return parts.joined(separator: " | ")
    }
    record("tracks", String(tracks.count))

    for (index, track) in tracks.enumerated() {
      let type = (try? await track.load(.mediaType)) ?? nil
      let size = (try? await track.load(.naturalSize)) ?? nil
      let rate = (try? await track.load(.nominalFrameRate)) ?? nil
      record(
        "track\(index)",
        "\(type?.rawValue ?? "unknown") \(Int(size?.width ?? 0))x\(Int(size?.height ?? 0))"
          + " fps=\(rate.map { String(format: "%.1f", Double($0)) } ?? "-")"
      )
    }

    return parts.joined(separator: " | ")
  }

  private static let surveyBudget: Double = 10

  /// Runs one question under a deadline, answering nil if it does not settle in
  /// time. The losing task is left to die rather than awaited: a load that never
  /// returns is exactly what this probe is looking for, and it is also what once
  /// hung a whole test session.
  private func settle<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T? {
    let claim = Claim()
    return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
      Task {
        let value = await work()
        if claim.take() { continuation.resume(returning: value) }
      }
      Task {
        try? await Task.sleep(for: .seconds(Self.surveyBudget))
        if claim.take() { continuation.resume(returning: nil) }
      }
    }
  }

  /// One answer per question, whichever task gets there first.
  private final class Claim: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    func take() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      if taken { return false }
      taken = true
      return true
    }
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
