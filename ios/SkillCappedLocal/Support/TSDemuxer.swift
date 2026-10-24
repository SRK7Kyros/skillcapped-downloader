import Foundation

/// One compressed sample out of a transport stream, in the shape a writer wants:
/// video as H.264 in AVCC form (every NAL prefixed with its 4-byte length) and
/// audio as a bare AAC frame (the ADTS header stripped). The stamps stay in the
/// stream's own 90 kHz clock, so a caller subtracts one base from both streams and
/// keeps them in step.
struct TSSample: Equatable {
  enum Kind: Equatable {
    case video
    case audio
  }

  let kind: Kind
  let payload: Data
  let pts: Int64
  let dts: Int64
  let isSync: Bool
}

/// What a stream declares about its video, and the one thing a writer cannot
/// guess: the parameter sets that begin every IDR frame.
struct TSVideoConfig: Equatable {
  let sps: Data
  let pps: Data
}

/// What a stream declares about its audio. `magicCookie` is the
/// `AudioSpecificConfig` the ADTS headers imply — the bytes an MP4 keeps inside
/// its own ES descriptor, which `TSRemux` wraps around them.
struct TSAudioConfig: Equatable {
  static let rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
                      16000, 12000, 11025, 8000, 7350]

  let objectType: Int
  let rateIndex: Int
  let channels: Int

  var sampleRate: Int {
    Self.rates.indices.contains(rateIndex) ? Self.rates[rateIndex] : 44100
  }

  var magicCookie: Data {
    let bits = ((objectType & 0x1f) << 11)
      | ((rateIndex & 0x0f) << 7)
      | ((channels & 0x0f) << 3)
    return Data([UInt8((bits >> 8) & 0xff), UInt8(bits & 0xff)])
  }
}

/// Reads an MPEG-TS file the way the platform cannot.
///
/// iOS ships no demuxer: a raw transport stream gives `AVURLAsset` an empty track
/// list, which is why a downloaded lesson plays through a one-segment HLS
/// playlist instead (`LessonServer`). Exporting one as a playable file needs its
/// packets taken apart here — PAT/PMT to find the two elementary streams, the PES
/// headers for the stamps, Annex-B turned into AVCC for the video and the ADTS
/// headers peeled off the audio — and that is all this does. It knows nothing
/// about writers, which is what makes it testable.
final class TSDemuxer {
  enum Failure: LocalizedError {
    case unreadable

    var errorDescription: String? {
      switch self {
      case .unreadable: return "That file could not be read."
      }
    }
  }

  static let packetSize = 188
  static let syncByte: UInt8 = 0x47
  static let clock: Int64 = 90_000
  private static let wrap: Int64 = 1 << 33

  /// Called on the thread that reads the file, once per sample, in the order the
  /// stream carries them — decode order, which is what a writer wants.
  var onSample: ((TSSample) -> Void)?

  private(set) var video: TSVideoConfig?
  private(set) var audio: TSAudioConfig?

  private var pmtPid: Int?
  private var videoPid: Int?
  private var audioPid: Int?
  private var partial: [Int: PES] = [:]
  private var carry = Data()

  private struct PES {
    var data: Data
    var pts: Int64?
    var dts: Int64?
  }

  /// Feed the file in chunks; call `flush()` once the last byte is in.
  func consume(_ chunk: Data) {
    carry.append(chunk)
    let bytes = [UInt8](carry)
    var offset = 0

    while bytes.count - offset >= Self.packetSize {
      // A chunk read from the middle of a file does not begin on a packet, and a
      // stream that loses a byte stays lost: walk to the sync byte, never assume.
      guard bytes[offset] == Self.syncByte else {
        offset += 1
        continue
      }
      packet(bytes, at: offset)
      offset += Self.packetSize
    }

    carry = Data(bytes[offset...])
  }

  /// The last PES packet has no successor to end it, so the caller says when.
  func flush() {
    for pid in [videoPid, audioPid].compactMap({ $0 }) {
      if let open = partial[pid] { finish(open, pid: pid) }
      partial[pid] = nil
    }
  }

  // MARK: - Packets

  private func packet(_ bytes: [UInt8], at start: Int) {
    let b1 = bytes[start + 1]
    guard b1 & 0x80 == 0 else { return }  // transport error: the packet is damaged
    let unitStart = b1 & 0x40 != 0
    let pid = (Int(b1 & 0x1f) << 8) | Int(bytes[start + 2])
    let control = (bytes[start + 3] >> 4) & 0x03

    var payload = start + 4
    if control & 0x02 != 0 {
      payload += 1 + Int(bytes[payload])
    }
    guard control & 0x01 != 0, payload < start + Self.packetSize else { return }
    let end = start + Self.packetSize

    if pid == 0 {
      program(bytes, payload, end)
    } else if pid == pmtPid {
      programMap(bytes, payload, end)
    } else if pid == videoPid || pid == audioPid {
      elementary(pid, unitStart, bytes, payload, end)
    }
  }

  /// PAT: which program, and the PID its PMT sits on.
  private func program(_ bytes: [UInt8], _ payload: Int, _ end: Int) {
    guard pmtPid == nil else { return }
    let table = sectionStart(bytes, payload, end)
    guard table >= 0, bytes[table] == 0x00, table + 12 <= end else { return }
    let length = (Int(bytes[table + 1] & 0x0f) << 8) | Int(bytes[table + 2])
    let stop = min(table + 3 + length - 4, end)
    var cursor = table + 8
    while cursor + 4 <= stop {
      let number = (Int(bytes[cursor]) << 8) | Int(bytes[cursor + 1])
      let target = (Int(bytes[cursor + 2] & 0x1f) << 8) | Int(bytes[cursor + 3])
      if number != 0 {
        pmtPid = target
        return
      }
      cursor += 4
    }
  }

  /// PMT: which PID carries H.264 and which carries AAC.
  private func programMap(_ bytes: [UInt8], _ payload: Int, _ end: Int) {
    guard videoPid == nil || audioPid == nil else { return }
    let table = sectionStart(bytes, payload, end)
    guard table >= 0, bytes[table] == 0x02, table + 12 <= end else { return }
    let length = (Int(bytes[table + 1] & 0x0f) << 8) | Int(bytes[table + 2])
    let stop = min(table + 3 + length - 4, end)
    let described = (Int(bytes[table + 10] & 0x0f) << 8) | Int(bytes[table + 11])

    var cursor = table + 12 + described
    while cursor + 5 <= stop {
      let type = bytes[cursor]
      let pid = (Int(bytes[cursor + 1] & 0x1f) << 8) | Int(bytes[cursor + 2])
      let described = (Int(bytes[cursor + 3] & 0x0f) << 8) | Int(bytes[cursor + 4])
      if type == 0x1b {
        videoPid = pid
      } else if type == 0x0f, audioPid == nil {
        audioPid = pid
      }
      cursor += 5 + described
    }
  }

  /// Where a section begins, past the pointer field a PES-less packet carries.
  private func sectionStart(_ bytes: [UInt8], _ payload: Int, _ end: Int) -> Int {
    guard payload < end else { return -1 }
    let start = payload + 1 + Int(bytes[payload])
    return start < end ? start : -1
  }

  /// One elementary stream's packets: a PES header when a new packet starts, its
  /// payload otherwise, assembled until the next header ends it.
  private func elementary(
    _ pid: Int,
    _ unitStart: Bool,
    _ bytes: [UInt8],
    _ payload: Int,
    _ end: Int
  ) {
    guard unitStart else {
      if var open = partial[pid] {
        open.data.append(contentsOf: bytes[payload..<end])
        partial[pid] = open
      }
      return
    }
    if let open = partial[pid] { finish(open, pid: pid) }
    partial[pid] = nil

    guard payload + 9 <= end,
          bytes[payload] == 0, bytes[payload + 1] == 0, bytes[payload + 2] == 1
    else { return }

    let flags = bytes[payload + 7]
    let header = Int(bytes[payload + 8])
    var pts: Int64?
    var dts: Int64?
    if flags & 0x80 != 0, payload + 14 <= end {
      pts = Self.stamp(bytes, payload + 9)
    }
    if flags & 0xc0 == 0xc0, payload + 19 <= end {
      dts = Self.stamp(bytes, payload + 14)
    }

    let body = payload + 9 + header
    guard body < end else { return }
    partial[pid] = PES(data: Data(bytes[body..<end]), pts: pts, dts: dts)
  }

  // MARK: - Samples

  private func finish(_ pes: PES, pid: Int) {
    guard let pts = pes.pts, !pes.data.isEmpty else { return }
    if pid == videoPid {
      videoSamples(pes, pts: pts)
    } else if pid == audioPid {
      audioSamples(pes, pts: pts)
    }
  }

  /// One frame per PES packet, which is how a segmented stream writes them. Its
  /// NAL units become length-prefixed ones, and the parameter sets it carries are
  /// kept aside: a writer wants them once, in the format description.
  private func videoSamples(_ pes: PES, pts: Int64) {
    let dts = pes.dts ?? pts
    var out = Data()
    var sync = false

    for nal in Self.nalUnits(pes.data) {
      guard let type = nal.first.map({ $0 & 0x1f }) else { continue }
      switch type {
      case 7:
        if video?.sps != nal { video = TSVideoConfig(sps: nal, pps: video?.pps ?? Data()) }
        continue
      case 8:
        if video?.pps != nal { video = TSVideoConfig(sps: video?.sps ?? Data(), pps: nal) }
        continue
      case 5:
        sync = true
      default:
        break
      }
      // AVCC: the unit's length in four bytes ahead of it, because an MP4 stores
      // lengths where a transport stream stores start codes.
      let length = UInt32(nal.count)
      out.append(UInt8((length >> 24) & 0xff))
      out.append(UInt8((length >> 16) & 0xff))
      out.append(UInt8((length >> 8) & 0xff))
      out.append(UInt8(length & 0xff))
      out.append(nal)
    }

    guard !out.isEmpty else { return }
    onSample?(TSSample(kind: .video, payload: out, pts: pts, dts: dts, isSync: sync))
  }

  /// The audio PES holds a whole number of ADTS frames, and each one is a sample:
  /// the header goes, the payload stays, and the stamp steps a frame at a time.
  private func audioSamples(_ pes: PES, pts: Int64) {
    let bytes = [UInt8](pes.data)
    var cursor = 0
    var index = 0

    while cursor + 7 <= bytes.count {
      guard bytes[cursor] == 0xff, bytes[cursor + 1] & 0xf0 == 0xf0 else {
        cursor += 1
        continue
      }
      let unprotected = bytes[cursor + 1] & 0x01 == 1
      let profile = Int((bytes[cursor + 2] >> 6) & 0x03)
      let rateIndex = Int((bytes[cursor + 2] >> 2) & 0x0f)
      let channels = (Int(bytes[cursor + 2] & 0x01) << 2)
        | Int((bytes[cursor + 3] >> 6) & 0x03)
      let length = (Int(bytes[cursor + 3] & 0x03) << 11)
        | (Int(bytes[cursor + 4]) << 3)
        | Int((bytes[cursor + 5] >> 5) & 0x07)
      let header = unprotected ? 7 : 9
      guard length > header, cursor + length <= bytes.count else { break }

      if audio == nil {
        audio = TSAudioConfig(objectType: profile + 1, rateIndex: rateIndex, channels: channels)
      }
      let config = audio ?? TSAudioConfig(objectType: 2, rateIndex: 4, channels: 2)
      let payload = Data(bytes[(cursor + header)..<(cursor + length)])
      let rate = Int64(max(config.sampleRate, 1))
      let step = (Int64(index) * 1024 * Self.clock + rate / 2) / rate
      let stamp = pts + step
      onSample?(TSSample(kind: .audio, payload: payload, pts: stamp, dts: stamp, isSync: true))

      index += 1
      cursor += length
    }
  }

  // MARK: - Bytes

  /// The 33-bit stamp a PES header carries, at a 3-byte start code plus one byte
  /// of flags.
  static func stamp(_ bytes: [UInt8], _ at: Int) -> Int64 {
    let high = Int64(bytes[at] & 0x0e) << 29
    let second = Int64(bytes[at + 1]) << 22
    let third = Int64(bytes[at + 2] & 0xfe) << 14
    let fourth = Int64(bytes[at + 3]) << 7
    let last = Int64(bytes[at + 4] >> 1)
    return (high | second | third | fourth | last) & (wrap - 1)
  }

  /// The NAL units inside a byte stream, start codes removed. A 4-byte start code
  /// is found at its third byte, which leaves the unit itself correct either way.
  static func nalUnits(_ data: Data) -> [Data] {
    let bytes = [UInt8](data)
    var starts: [Int] = []
    var cursor = 0
    while cursor + 3 <= bytes.count {
      if bytes[cursor] == 0, bytes[cursor + 1] == 0, bytes[cursor + 2] == 1 {
        starts.append(cursor + 3)
        cursor += 3
      } else {
        cursor += 1
      }
    }
    guard !starts.isEmpty else { return [] }

    var units: [Data] = []
    for (index, start) in starts.enumerated() {
      let limit = index + 1 < starts.count ? starts[index + 1] - 3 : bytes.count
      guard limit > start else { continue }
      var end = limit
      // Trailing zeroes belong to the next start code, not to this unit.
      while end > start, bytes[end - 1] == 0 { end -= 1 }
      guard end > start else { continue }
      units.append(Data(bytes[start..<end]))
    }
    return units
  }
}

/// What a stream has to say before it is worth writing: which parameter sets its
/// video begins with, how its audio is configured, and where its clock starts —
/// both streams measured against the same zero, or a lesson exports with its
/// sound a tenth of a second off.
enum TSStreamProbe {
  struct Result {
    let video: TSVideoConfig?
    let audio: TSAudioConfig?
    let base: Int64
  }

  /// Enough of the head to hold the first key frame and a few audio packets, and
  /// no more: a lesson can be a gigabyte.
  static let window = 2 << 20

  static func run(url: URL, window: Int = window) throws -> Result {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      throw TSDemuxer.Failure.unreadable
    }
    defer { try? handle.close() }
    let head = (try? handle.read(upToCount: window)) ?? Data()
    guard !head.isEmpty else { throw TSDemuxer.Failure.unreadable }

    let demuxer = TSDemuxer()
    var base: Int64?
    demuxer.onSample = { sample in
      if base == nil || sample.dts < base! { base = sample.dts }
    }
    demuxer.consume(head)

    return Result(
      video: demuxer.video,
      audio: demuxer.audio,
      base: max(base ?? 0, 0)
    )
  }
}
