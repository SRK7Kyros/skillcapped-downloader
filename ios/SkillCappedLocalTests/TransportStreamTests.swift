import XCTest

@testable import SkillCappedLocal

final class TransportStreamTests: XCTestCase {
  private let clock: UInt64 = 90_000

  /// One 188-byte packet carrying the start of a PES with a single timestamp.
  private func packet(pid: UInt16 = 0x100, pts: UInt64, adaptation: Bool = false) -> [UInt8] {
    var bytes = [UInt8](repeating: 0xFF, count: TransportStream.packetSize)
    bytes[0] = TransportStream.syncByte
    bytes[1] = 0x40 | UInt8((pid >> 8) & 0x1F)
    bytes[2] = UInt8(pid & 0xFF)
    bytes[3] = adaptation ? 0x30 : 0x10

    var head = 4
    if adaptation {
      bytes[4] = 7
      head = 12
    }
    bytes[head] = 0
    bytes[head + 1] = 0
    bytes[head + 2] = 1
    bytes[head + 3] = 0xE0
    bytes[head + 7] = 0x80
    bytes[head + 9] = UInt8((pts >> 29) & 0x0E) | 0x21
    bytes[head + 10] = UInt8((pts >> 22) & 0xFF)
    bytes[head + 11] = UInt8((pts >> 14) & 0xFE) | 0x01
    bytes[head + 12] = UInt8((pts >> 7) & 0xFF)
    bytes[head + 13] = UInt8((pts << 1) & 0xFE) | 0x01
    return bytes
  }

  private func stream(_ stamps: [UInt64], adaptation: Bool = false) -> Data {
    Data(stamps.flatMap { packet(pts: $0, adaptation: adaptation) })
  }

  func testTheSpanBetweenTwoStampsIsTheLength() {
    XCTAssertEqual(TransportStream.seconds(first: 0, last: clock * 57) ?? 0, 57, accuracy: 0.001)
    XCTAssertEqual(TransportStream.seconds(first: clock * 120, last: clock * 180) ?? 0, 60, accuracy: 0.001)
  }

  func testAStampIsReadOutOfAPacketWithAPayload() {
    let stamps = [clock * 12, clock * 13, clock * 14, clock * 15]
    XCTAssertEqual(TransportStream.timestamps(in: stream(stamps)), stamps)
  }

  /// Adaptation fields put the payload after their own length byte, and a real
  /// CDN part starts its first video packet exactly that way.
  func testAStampIsReadPastAnAdaptationField() {
    let stamps = [clock * 30, clock * 31, clock * 32, clock * 33]
    XCTAssertEqual(TransportStream.timestamps(in: stream(stamps, adaptation: true)), stamps)
  }

  /// A chunk read from the middle of a file almost never starts on a packet
  /// boundary, so the sync byte is found by asking three packets to agree.
  func testAMisalignedChunkStillFindsItsStamps() {
    let stamps = [clock * 5, clock * 6, clock * 7, clock * 8]
    let shifted = Data([0x00, 0x11, 0x22]) + stream(stamps)
    XCTAssertEqual(TransportStream.timestamps(in: shifted), stamps)
  }

  func testAPacketWithoutPayloadIsIgnored() {
    var bytes = packet(pts: 0)
    bytes[3] = 0x20
    XCTAssertEqual(TransportStream.timestamps(in: Data(bytes + bytes + bytes + bytes)), [])
  }

  func testRandomBytesYieldNothing() {
    let noise = Data((0..<(TransportStream.packetSize * 8)).map { _ in UInt8.random(in: 0...255) })
    XCTAssertEqual(TransportStream.timestamps(in: noise), [])
  }

  /// The counter is 33 bits wide, so a stream longer than 26 hours wraps — and a
  /// wrap is recoverable while a clock that restarts part-way is not.
  func testAWrappedCounterIsRecoveredAndARestartedOneIsNot() {
    let wrap: UInt64 = 1 << 33
    let recovered = TransportStream.seconds(first: wrap - clock * 10, last: clock * 30)
    XCTAssertEqual(recovered ?? 0, 40, accuracy: 0.01)

    XCTAssertNil(TransportStream.seconds(first: clock * 400, last: clock * 10), "a clock that jumped backwards lies")
    XCTAssertNil(TransportStream.seconds(first: 0, last: 0), "a zero span is not a duration")
    XCTAssertNil(TransportStream.seconds(first: 0, last: clock * 60 * 60 * 24), "a day is not a lesson")
  }

  /// A real part from the CDN, 62 KB and about three seconds long: the numbers
  /// read off it are the ones the player would be told.
  func testTheLengthIsMeasuredOffARealStream() throws {
    let file = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "lesson", withExtension: "ts"),
      "the test bundle is missing Fixtures/lesson.ts"
    )
    let seconds = try XCTUnwrap(TransportStream.seconds(of: file), "the fixture states no timestamps")
    XCTAssertTrue((2...4).contains(seconds), "the fixture is about three seconds long, not \(seconds)")
  }

  func testAFileThatStatesNothingAnswersNothing() throws {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("empty-\(UUID().uuidString).ts")
    defer { try? FileManager.default.removeItem(at: file) }
    XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data(repeating: 0, count: 4096)))

    XCTAssertNil(TransportStream.seconds(of: file))
    XCTAssertNil(TransportStream.seconds(of: file.appendingPathExtension("missing")))
  }
}
