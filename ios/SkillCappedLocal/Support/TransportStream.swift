import Foundation

/// A transport stream states its own timeline: every PES packet that begins a
/// frame carries a 90 kHz presentation timestamp, so the last one less the first
/// is how long the file plays.
///
/// iOS has no MPEG-TS demuxer, which is why a downloaded lesson is served to the
/// player as a one-segment HLS playlist — and that playlist has to declare a
/// duration. Without this, a file the catalogue does not know would be declared
/// an hour long and the player would show an hour-long window for a ten-minute
/// lesson.
enum TransportStream {
  static let packetSize = 188
  static let syncByte: UInt8 = 0x47
  static let clock: Double = 90_000
  /// How much of each end of the file is read. Timestamps are dense enough that a
  /// megabyte holds plenty, and a lesson can be a gigabyte.
  static let window = 1 << 20
  private static let wrap: UInt64 = 1 << 33
  private static let ceiling: Double = 12 * 3600

  /// The seconds the stream covers, or nil when it does not say.
  static func seconds(of url: URL) -> Int? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

    // Back to the start before reading: seeking to the end to learn the size left
    // the handle there, and a read at the end answers nothing at all.
    _ = try? handle.seek(toOffset: 0)
    let head = (try? handle.read(upToCount: window)) ?? Data()
    let tailStart = size > UInt64(window) ? size - UInt64(window) : 0
    try? handle.seek(toOffset: tailStart)
    let tail = (try? handle.read(upToCount: window)) ?? Data()

    guard let first = timestamps(in: head).first,
          let last = timestamps(in: tail).last,
          let length = seconds(first: first, last: last)
    else { return nil }
    return Int(length.rounded())
  }

  /// The span between two 33-bit timestamps. A counter that wrapped once is
  /// recoverable; a stream that restarts its clock part-way — a file merged from
  /// parts that each began at zero — is not, and answers nil so the caller keeps
  /// its placeholder instead of showing a lie.
  static func seconds(first: UInt64, last: UInt64) -> Double? {
    let span = last >= first ? last - first : last &+ wrap &- first
    let length = Double(span) / clock
    guard length > 0.5, length < ceiling else { return nil }
    return length
  }

  /// Every presentation timestamp in a chunk, in the order the packets appear.
  /// The first sync byte is found by asking three consecutive packets to agree,
  /// because a chunk read from the middle of a file almost never starts on one.
  static func timestamps(in data: Data) -> [UInt64] {
    let bytes = [UInt8](data)
    guard bytes.count > packetSize * 3 else { return [] }

    var origin = -1
    var probe = 0
    while probe + packetSize * 2 < bytes.count {
      if bytes[probe] == syncByte,
         bytes[probe + packetSize] == syncByte,
         bytes[probe + packetSize * 2] == syncByte {
        origin = probe
        break
      }
      probe += 1
    }
    guard origin >= 0 else { return [] }

    var stamps: [UInt64] = []
    var cursor = origin
    while cursor + packetSize <= bytes.count {
      if bytes[cursor] == syncByte {
        if let stamp = timestamp(bytes, at: cursor) { stamps.append(stamp) }
        cursor += packetSize
      } else {
        cursor += 1
      }
    }
    return stamps
  }

  private static func timestamp(_ bytes: [UInt8], at packet: Int) -> UInt64? {
    let b1 = bytes[packet + 1]
    let b2 = bytes[packet + 2]
    let b3 = bytes[packet + 3]
    guard b1 & 0x40 != 0 else { return nil }
    guard b3 & 0x10 != 0 else { return nil }
    let pid = (UInt16(b1 & 0x1F) << 8) | UInt16(b2)
    guard pid != 0x1FFF else { return nil }

    var start = packet + 4
    if b3 & 0x20 != 0 {
      // The length byte itself counts: the payload starts one byte after it.
      start += Int(bytes[start]) + 1
    }
    guard start + 14 < packet + packetSize else { return nil }
    guard bytes[start] == 0, bytes[start + 1] == 0, bytes[start + 2] == 1 else { return nil }
    guard bytes[start + 7] & 0x80 != 0 else { return nil }

    let base = start + 9
    return (UInt64(bytes[base] & 0x0E) << 29)
      | (UInt64(bytes[base + 1]) << 22)
      | (UInt64(bytes[base + 2] & 0xFE) << 14)
      | (UInt64(bytes[base + 3]) << 7)
      | (UInt64(bytes[base + 4] >> 1))
  }
}
