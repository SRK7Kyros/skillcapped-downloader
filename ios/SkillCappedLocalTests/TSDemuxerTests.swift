import AVFoundation
import XCTest

@testable import SkillCappedLocal

/// The demuxer against a real transport stream, because the only question that
/// matters is whether it reads the packets a CDN actually wrote.
///
/// The fixture is one small lesson: a PAT/PMT, H.264 with two key frames and AAC
/// at 22.05 kHz, about three seconds long. The numbers below were taken off it by
/// hand once, so a regression in any part — packet assembly, the stamps, the NAL
/// rewrite, the ADTS walk — moves one of them.
final class TSDemuxerTests: XCTestCase {
  private func fixture() throws -> URL {
    try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "lesson", withExtension: "ts"),
      "the test bundle is missing Fixtures/lesson.ts"
    )
  }

  private struct Reading {
    var video: [TSSample] = []
    var audio: [TSSample] = []

    var all: [TSSample] { video + audio }
  }

  private func read(_ url: URL, chunk: Int = 64 * 1024, flush: Bool = true) throws -> Reading {
    let demuxer = TSDemuxer()
    var reading = Reading()
    demuxer.onSample = { sample in
      switch sample.kind {
      case .video: reading.video.append(sample)
      case .audio: reading.audio.append(sample)
      }
    }

    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    while let data = try handle.read(upToCount: chunk), !data.isEmpty {
      demuxer.consume(data)
    }
    if flush { demuxer.flush() }
    return reading
  }

  /// The NAL units out of one assembled sample, in order, taken by walking its
  /// four-byte lengths — which is itself the check that it was rewritten.
  private func units(_ payload: Data) -> [Data] {
    let bytes = [UInt8](payload)
    var out: [Data] = []
    var cursor = 0
    while cursor + 4 <= bytes.count {
      let length = (Int(bytes[cursor]) << 24) | (Int(bytes[cursor + 1]) << 16)
        | (Int(bytes[cursor + 2]) << 8) | Int(bytes[cursor + 3])
      guard length > 0, cursor + 4 + length <= bytes.count else { break }
      out.append(Data(bytes[(cursor + 4)..<(cursor + 4 + length)]))
      cursor += 4 + length
    }
    return out
  }

  // MARK: - What the stream declares

  func testTheStreamDeclaresItsVideoAndItsSound() throws {
    let probe = try TSStreamProbe.run(url: try fixture())

    let video = try XCTUnwrap(probe.video, "the fixture carries no H.264")
    XCTAssertEqual(video.sps.count, 26)
    XCTAssertEqual(
      [UInt8](video.sps.prefix(6)),
      [0x67, 0x64, 0x00, 0x15, 0xac, 0xd9],
      "the sequence parameter set should come through unsorted"
    )
    XCTAssertEqual(video.pps.count, 5)

    let audio = try XCTUnwrap(probe.audio, "the fixture carries no AAC")
    XCTAssertEqual(audio.objectType, 2, "AAC LC is what every CDN writes")
    XCTAssertEqual(audio.sampleRate, 22_050)
    XCTAssertEqual(audio.channels, 2)
    XCTAssertEqual(
      [UInt8](audio.magicCookie),
      [0x13, 0x90],
      "the AudioSpecificConfig is the ADTS headers in two bytes"
    )
  }

  /// A stream that starts at 126000 is normal — a segment cut out of a longer
  /// broadcast keeps the broadcast's clock, and a writer has to subtract a base
  /// before it can place anything at all.
  func testTheBaseIsTheEarliestStampInTheFile() throws {
    let probe = try TSStreamProbe.run(url: try fixture())
    XCTAssertEqual(probe.base, 126_000)
  }

  // MARK: - The samples

  func testEveryPacketOfTheFileBecomesASample() throws {
    let reading = try read(try fixture())
    XCTAssertEqual(reading.video.count, 45)
    XCTAssertEqual(reading.audio.count, 66)
  }

  /// One PES carries one video frame, in decode order — which is not presentation
  /// order, because the fixture has B-frames.
  func testTheFirstVideoFrameIsAKeyFrameCarryingItsOwnPrefix() throws {
    let reading = try read(try fixture())
    let first = try XCTUnwrap(reading.video.first)

    XCTAssertTrue(first.isSync, "the first frame of a segment is a key frame")
    XCTAssertEqual(first.pts, 138_000)
    XCTAssertEqual(first.dts, 126_000, "the frame decodes before it is shown")

    let units = units(first.payload)
    XCTAssertEqual(
      units.compactMap { $0.first.map { $0 & 0x1f } },
      [9, 6, 5],
      "an access unit delimiter, a SEI and the IDR — nothing else"
    )
    XCTAssertEqual(first.payload.count, 3_267)
  }

  /// The parameter sets belong in the format description, not in every frame: an
  /// MP4 that repeated them per sample would play, and waste a kilobyte a second.
  func testTheParameterSetsAreKeptOutOfTheFrames() throws {
    let reading = try read(try fixture())
    let types = reading.video.flatMap { sample in
      units(sample.payload).compactMap { $0.first.map { $0 & 0x1f } }
    }
    XCTAssertFalse(types.contains(7), "no sequence parameter set should reach a frame")
    XCTAssertFalse(types.contains(8), "no picture parameter set should reach a frame")
    XCTAssertEqual(reading.video.filter(\.isSync).count, 2, "the fixture holds two IDRs")
  }

  func testTheFramesAreLengthPrefixedEndToEnd() throws {
    let reading = try read(try fixture())
    for sample in reading.video {
      let units = units(sample.payload)
      XCTAssertEqual(
        units.reduce(4 * units.count) { $0 + $1.count },
        sample.payload.count,
        "every byte of a frame should sit behind exactly one length"
      )
    }
  }

  /// The audio PES holds a run of ADTS frames, and each one is a sample of its own:
  /// the header goes and the stamp steps a frame at a time, so the sound stays in
  /// step with the picture instead of arriving one packet per packet.
  func testTheSoundIsSplitIntoFramesOnItsOwnClock() throws {
    let reading = try read(try fixture())
    let first = try XCTUnwrap(reading.audio.first)

    XCTAssertEqual(first.pts, 133_820, "the sound starts before the first picture")
    XCTAssertEqual(first.payload.count, 23, "an AAC frame at 22.05 kHz is short")
    XCTAssertEqual(first.dts, first.pts, "a sound frame has one stamp")

    let step = reading.audio[1].pts - reading.audio[0].pts
    // 1024 samples at 22050 Hz, in the stream's 90 kHz clock: 4179.6 ticks.
    XCTAssertTrue((4_170...4_190).contains(step), "a frame should step \(step) ticks")
    for pair in zip(reading.audio, reading.audio.dropFirst()) {
      XCTAssertGreaterThan(pair.1.pts, pair.0.pts, "the sound should stay in order")
    }
  }

  // MARK: - Reading in pieces

  /// A file arrives in 4 MB chunks and the packets do not respect the boundary, so
  /// the same file read in odd pieces has to come out the same.
  func testThePiecesOfAChunkedReadAreAssembledIntoTheSameSamples() throws {
    let url = try fixture()
    let whole = try read(url, chunk: 1 << 20)
    let pieces = try read(url, chunk: 188 * 3 + 7)

    XCTAssertEqual(pieces.video.count, whole.video.count)
    XCTAssertEqual(pieces.audio.count, whole.audio.count)
    XCTAssertEqual(pieces.video.first?.payload, whole.video.first?.payload)
    XCTAssertEqual(pieces.audio.last?.pts, whole.audio.last?.pts)
  }

  func testAFileThatCannotBeReadIsRefused() throws {
    let empty = FileManager.default.temporaryDirectory
      .appendingPathComponent("empty-\(UUID().uuidString).ts")
    XCTAssertTrue(FileManager.default.createFile(atPath: empty.path, contents: Data()))
    defer { try? FileManager.default.removeItem(at: empty) }

    XCTAssertThrowsError(try TSStreamProbe.run(url: empty))
    XCTAssertThrowsError(
      try TSStreamProbe.run(url: empty.deletingLastPathComponent().appendingPathComponent("gone.ts"))
    )
  }

  // MARK: - The remux

  /// A value a background job fills in and the test reads afterwards.
  private final class Handoff<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    var value: T? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return stored
      }
      set {
        lock.lock()
        stored = newValue
        lock.unlock()
      }
    }
  }

  /// The reports a repackaging makes, kept where the job writes them.
  private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func add(_ value: Double) {
      lock.lock()
      values.append(value)
      lock.unlock()
    }

    var count: Int {
      lock.lock()
      defer { lock.unlock() }
      return values.count
    }

    var last: Double? {
      lock.lock()
      defer { lock.unlock() }
      return values.last
    }
  }

  /// What a repackaging gave, or how it says it went wrong — a plain value, so
  /// it can cross a thread boundary in one piece.
  private enum Outcome: Sendable {
    case done(Double)
    case failed(String)
  }

  /// Runs a job off the main thread and answers what it gave, or nil if it never
  /// answered. The writer's own callbacks must not queue behind the thread that
  /// is watching it: a synchronous call here left the video track refusing data
  /// for ever, with the writer still `writing` and no error to show.
  private func offMain<T: Sendable>(_ job: @escaping @Sendable () -> T) -> T? {
    let handoff = Handoff<T>()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
      handoff.value = job()
      done.signal()
    }
    done.wait()
    return handoff.value
  }

  /// The whole pipeline once, because each part can look right on its own and
  /// still not add up to a file anything will open: a demuxed sample is only
  /// useful if the writer accepts it.
  func testTheFixtureRepackagesIntoAnMP4WithBothTracks() async throws {
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("remux-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: destination) }

    let reports = Reports()
    let source = try fixture()
    let produced = try read(source)
    let demuxed = "the file demuxes to \(produced.video.count) picture and \(produced.audio.count) sound samples"
    let outcome = offMain { () -> Outcome in
      do {
        return .done(
          try TSRemux.toMP4(
            source: source,
            destination: destination,
            progress: { reports.add($0) }
          )
        )
      } catch {
        let cocoa = error as NSError
        return .failed(
          """
          \(String(describing: type(of: error))) (\(cocoa.domain) \(cocoa.code)) \
          after \(reports.count) reports, last \(reports.last ?? -1): \
          \(cocoa.localizedDescription)
          """
        )
      }
    }

    let seconds: Double
    switch outcome {
    case let .done(value)?:
      seconds = value
    case let .failed(reason)?:
      XCTFail("the repackaging threw \(reason)")
      return
    case nil:
      XCTFail("the repackaging never answered")
      return
    }

    XCTAssertEqual(reports.last, 1, "the progress should finish where the banner says it does")
    XCTAssertTrue((2...4).contains(seconds), "the fixture is about three seconds, not \(seconds)")

    let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64
    XCTAssertGreaterThan(size ?? 0, 4_096, "an MP4 of three seconds is more than its headers")

    let asset = AVURLAsset(url: destination)
    do {
      let video = try await asset.loadTracks(withMediaType: .video)
      let audio = try await asset.loadTracks(withMediaType: .audio)
      XCTAssertEqual(video.count, 1, "the picture should survive the repackaging — \(demuxed)")
      XCTAssertEqual(audio.count, 1, "and so should the sound — \(demuxed)")

      let duration = try await asset.load(.duration).seconds
      XCTAssertTrue((2...4).contains(duration), "the MP4 runs about three seconds, not \(duration)")
    } catch {
      XCTFail("the written MP4 could not be read back: \(error)")
    }
  }

  /// Stopping leaves nothing behind: a half-written MP4 is worse than no file, and
  /// the bytes are still on disk under their own name.
  func testStoppingTheRepackagingLeavesNoFile() throws {
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("stopped-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: destination) }

    XCTAssertThrowsError(
      try TSRemux.toMP4(source: try fixture(), destination: destination, cancelled: { true })
    ) { error in
      guard let failure = error as? TSRemux.Failure, case .cancelled = failure else {
        return XCTFail("stopping should answer cancelled, not \(error)")
      }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }
}
