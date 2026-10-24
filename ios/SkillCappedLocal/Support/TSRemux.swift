import AVFoundation
import CoreMedia
import Foundation

/// Turns a downloaded `.ts` into an `.mp4` the rest of the world can open — and
/// that this phone could play without the HLS shell if it wanted to.
///
/// There is no system demuxer to lean on, so the samples come from `TSDemuxer`
/// and go straight back out through `AVAssetWriter` with no re-encode: the H.264
/// and AAC bytes are already exactly what an MP4 carries, so only the container
/// changes. That makes it a copy rather than an encode — a lesson-sized file is
/// minutes of reading, not hours of transcoding.
enum TSRemux {
  enum Failure: LocalizedError {
    case noVideo
    case unusableVideo
    case unusableAudio
    case writer(String)
    case cancelled

    var errorDescription: String? {
      switch self {
      case .noVideo:
        return "That file does not hold a video track this app can read."
      case .unusableVideo:
        return "The lesson's video cannot be repackaged."
      case .unusableAudio:
        return "The lesson's sound cannot be repackaged."
      case let .writer(reason):
        return "The MP4 could not be written: \(reason)"
      case .cancelled:
        return "The export was stopped."
      }
    }
  }

  /// How much is read at a time. Large enough that a gigabyte is a few hundred
  /// reads, small enough that cancelling is felt at once.
  static let chunk = 4 << 20

  /// How many samples a track may hold before the reader is held back. A couple
  /// of seconds: enough that the writer is never left waiting for the reader,
  /// small enough that a lesson is never carried in memory.
  static let backlog = 96

  /// Rewrites `source` into `destination`, reporting how much of the file has
  /// been read (0…1) and answering how many seconds it holds.
  ///
  /// Blocking on purpose: the caller runs it off the main actor.
  @discardableResult
  static func toMP4(
    source: URL,
    destination: URL,
    progress: (Double) -> Void = { _ in },
    cancelled: () -> Bool = { false }
  ) throws -> Double {
    let probe = try TSStreamProbe.run(url: source)
    guard let videoConfig = probe.video, !videoConfig.sps.isEmpty, !videoConfig.pps.isEmpty else {
      throw Failure.noVideo
    }
    let videoFormat = try videoDescription(videoConfig)
    let audioFormat = try probe.audio.map { try audioDescription($0) }
    let base = probe.base
    let audioFrame = CMTime(
      value: 1024,
      timescale: CMTimeScale(max(probe.audio?.sampleRate ?? 44100, 1))
    )

    try? FileManager.default.removeItem(at: destination)
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    } catch {
      throw Failure.writer("the file could not be started: \(error.localizedDescription)")
    }

    let video = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: nil,
      sourceFormatHint: videoFormat
    )
    video.expectsMediaDataInRealTime = false
    guard writer.canAdd(video) else { throw Failure.writer("the video track was refused") }
    writer.add(video)

    var sound: AVAssetWriterInput?
    if let audioFormat {
      let input = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: nil,
        sourceFormatHint: audioFormat
      )
      input.expectsMediaDataInRealTime = false
      // Only a video track takes a media time scale: asking an audio one for a
      // non-default value raises, which is how this was learned.
      guard writer.canAdd(input) else { throw Failure.writer("the sound track was refused") }
      writer.add(input)
      sound = input
    }

    guard writer.startWriting() else {
      throw Failure.writer(writer.error?.localizedDescription ?? "the writer did not start")
    }
    writer.startSession(atSourceTime: .zero)

    var tracks = [Interleaver.Track(input: video, format: videoFormat)]
    if let sound, let audioFormat {
      tracks.append(Interleaver.Track(input: sound, format: audioFormat))
    }
    let interleaver = Interleaver(writer: writer, tracks: tracks)
    let hasSound = tracks.count > 1

    /// The frame waiting for the next one, because a sample's duration is the gap
    /// to its successor and the last one has none.
    var pending: (payload: Data, pts: Int64, dts: Int64, sync: Bool)?
    var lastTicks: Int64 = 3_000
    var end: Int64 = 0
    var failure: Error?

    let clock = CMTimeScale(TSDemuxer.clock)
    let demuxer = TSDemuxer()
    demuxer.onSample = { sample in
      guard failure == nil else { return }
      do {
        let pts = sample.pts - base
        let dts = sample.dts - base
        // A stamp before the file's own first one belongs to an earlier part of
        // a merged stream, which an MP4 cannot place.
        guard pts >= 0, dts >= 0 else { return }

        switch sample.kind {
        case .video:
          if let previous = pending {
            let ticks = max(dts - previous.dts, 1)
            lastTicks = ticks
            try interleaver.add(
              Interleaver.Sample(
                payload: previous.payload,
                pts: CMTime(value: previous.pts, timescale: clock),
                dts: CMTime(value: previous.dts, timescale: clock),
                duration: CMTime(value: ticks, timescale: clock),
                sync: previous.sync
              ),
              track: 0
            )
          }
          pending = (sample.payload, pts, dts, sample.isSync)
          end = max(end, pts)

        case .audio:
          guard hasSound else { return }
          try interleaver.add(
            Interleaver.Sample(
              payload: sample.payload,
              pts: CMTime(value: pts, timescale: clock),
              dts: CMTime(value: pts, timescale: clock),
              duration: audioFrame,
              sync: true
            ),
            track: 1
          )
          end = max(end, pts)
        }
      } catch {
        failure = error
      }
    }

    do {
      let handle = try FileHandle(forReadingFrom: source)
      defer { try? handle.close() }
      let total = (try? FileManager.default.attributesOfItem(atPath: source.path))
        .flatMap { $0[.size] as? NSNumber }?
        .doubleValue ?? 0
      var read = 0

      while true {
        if cancelled() { throw Failure.cancelled }
        guard let chunk = try handle.read(upToCount: chunk), !chunk.isEmpty else { break }
        read += chunk.count
        demuxer.consume(chunk)
        if let failure { throw failure }
        progress(min(Double(read) / max(total, 1), 1))
      }

      demuxer.flush()
      if let failure { throw failure }

      if let previous = pending {
        try interleaver.add(
          Interleaver.Sample(
            payload: previous.payload,
            pts: CMTime(value: previous.pts, timescale: clock),
            dts: CMTime(value: previous.dts, timescale: clock),
            duration: CMTime(value: lastTicks, timescale: clock),
            sync: previous.sync
          ),
          track: 0
        )
        pending = nil
        end = max(end, previous.pts + lastTicks)
      }

      try interleaver.finish()
      try interleaver.check()
    } catch {
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: destination)
      throw error
    }

    video.markAsFinished()
    sound?.markAsFinished()

    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()

    guard writer.status == .completed else {
      try? FileManager.default.removeItem(at: destination)
      throw Failure.writer(writer.error?.localizedDescription ?? "the writer did not finish")
    }
    progress(1)
    return Double(end) / Double(TSDemuxer.clock)
  }

  // MARK: - Frames

  private static func sampleBuffer(
    _ payload: Data,
    format: CMFormatDescription,
    pts: CMTime,
    dts: CMTime,
    duration: CMTime,
    sync: Bool
  ) throws -> CMSampleBuffer {
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: payload.count,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: payload.count,
      flags: 0,
      blockBufferOut: &block
    ) == kCMBlockBufferNoErr, let block else {
      throw Failure.writer("a sample's memory could not be made")
    }

    let copied = payload.withUnsafeBytes { raw in
      CMBlockBufferReplaceDataBytes(
        with: raw.baseAddress!,
        blockBuffer: block,
        offsetIntoDestination: 0,
        dataLength: payload.count
      )
    }
    guard copied == kCMBlockBufferNoErr else {
      throw Failure.writer("a sample's bytes could not be copied")
    }

    var size = payload.count
    var timing = CMSampleTimingInfo(
      duration: duration,
      presentationTimeStamp: pts,
      decodeTimeStamp: dts
    )
    var buffer: CMSampleBuffer?
    guard CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: block,
      formatDescription: format,
      sampleCount: 1,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleSizeEntryCount: 1,
      sampleSizeArray: &size,
      sampleBufferOut: &buffer
    ) == noErr, let buffer else {
      throw Failure.writer("a sample could not be framed")
    }

    // Only a key frame may start playback, and an MP4 records that per sample:
    // without it every frame is called a key frame and seeking lands on a delta
    // frame, which decodes to a smear.
    if !sync,
       let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0 {
      let dictionary = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0),
        to: CFMutableDictionary.self
      )
      CFDictionarySetValue(
        dictionary,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
      )
    }
    return buffer
  }

  // MARK: - Interleaving

  /// Holds each track's samples until the writer will take them.
  ///
  /// An `AVAssetWriter` writes the tracks interleaved and stops taking data for
  /// a track that has run ahead of the other, offering it again only once the
  /// other has caught up. So a track can never be waited on by itself: the wait
  /// would hold back the very samples that let the writer resume, and the export
  /// would stop dead with the writer still `writing` and no error to show. Both
  /// queues are therefore emptied together, always.
  private final class Interleaver {
    struct Sample {
      let payload: Data
      let pts: CMTime
      let dts: CMTime
      let duration: CMTime
      let sync: Bool
    }

    final class Track {
      let input: AVAssetWriterInput
      let format: CMFormatDescription
      var samples: [Sample] = []
      var fed = 0

      init(input: AVAssetWriterInput, format: CMFormatDescription) {
        self.input = input
        self.format = format
      }
    }

    private let writer: AVAssetWriter
    private let tracks: [Track]

    init(writer: AVAssetWriter, tracks: [Track]) {
      self.writer = writer
      self.tracks = tracks
    }

    var isFull: Bool { tracks.contains { $0.samples.count > TSRemux.backlog } }

    var isEmpty: Bool { tracks.allSatisfy { $0.samples.isEmpty } }

    /// Queues one sample and hands the writer whatever it will take, waiting
    /// only while a track is carrying more than it should.
    func add(_ sample: Sample, track index: Int) throws {
      tracks[index].samples.append(sample)
      try pump(until: { !isFull }, abandoning: true)
    }

    /// Hands over everything still queued, waiting for the writer to want it.
    func finish() throws {
      try pump(until: { isEmpty }, abandoning: false)
    }

    /// A track the writer took no samples for is left out of the file, so an
    /// export can come back with its sound simply gone and no error anywhere.
    func check() throws {
      for track in tracks where track.fed == 0 {
        let kind = track.input.mediaType == .video ? "picture" : "sound"
        throw Failure.writer("the \(kind) track was given no samples (\(tally))")
      }
    }

    /// Empties both queues as the writer asks. With `abandoning`, a writer that
    /// will take nothing while another track has nothing left to hand over is
    /// left to finish what it has: only the reader can end that wait, so
    /// standing still would stop the export instead of pacing it.
    private func pump(until settled: () -> Bool, abandoning: Bool) throws {
      var waited = 0.0
      while true {
        var moved = false
        for track in tracks {
          while track.input.isReadyForMoreMediaData, !track.samples.isEmpty {
            try feed(track, track.samples.removeFirst())
            track.fed += 1
            moved = true
          }
        }
        if settled() { return }
        if abandoning, !moved, tracks.contains(where: { $0.samples.isEmpty }) { return }
        if let reason = writer.error {
          throw Failure.writer("the writer refused a sample: \(reason.localizedDescription)")
        }
        guard writer.status == .writing, waited < 20 else {
          throw Failure.writer(
            "the writer stopped accepting data (status \(writer.status.rawValue); \(tally) written)"
          )
        }
        Thread.sleep(forTimeInterval: 0.002)
        waited += 0.002
      }
    }

    private func feed(_ track: Track, _ sample: Sample) throws {
      let buffer = try TSRemux.sampleBuffer(
        sample.payload,
        format: track.format,
        pts: sample.pts,
        dts: sample.dts,
        duration: sample.duration,
        sync: sample.sync
      )
      guard track.input.append(buffer) else {
        throw Failure.writer(writer.error?.localizedDescription ?? "a sample was refused")
      }
    }

    private var tally: String {
      tracks
        .map { "\($0.input.mediaType == .video ? "picture" : "sound") \($0.fed)" }
        .joined(separator: ", ")
    }
  }

  // MARK: - Format descriptions

  private static func videoDescription(_ config: TSVideoConfig) throws -> CMFormatDescription {
    let sps = [UInt8](config.sps)
    let pps = [UInt8](config.pps)
    var description: CMFormatDescription?

    let status = sps.withUnsafeBufferPointer { first in
      pps.withUnsafeBufferPointer { second in
        var pointers = [first.baseAddress!, second.baseAddress!]
        var sizes = [sps.count, pps.count]
        return pointers.withUnsafeMutableBufferPointer { pointers in
          sizes.withUnsafeMutableBufferPointer { sizes in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
              allocator: kCFAllocatorDefault,
              parameterSetCount: 2,
              parameterSetPointers: pointers.baseAddress!,
              parameterSetSizes: sizes.baseAddress!,
              nalUnitHeaderLength: 4,
              formatDescriptionOut: &description
            )
          }
        }
      }
    }
    guard status == noErr, let description else { throw Failure.unusableVideo }
    return description
  }

  /// The AAC format an MP4 wants: an ES descriptor wrapped around the stream's
  /// own `AudioSpecificConfig`.
  ///
  /// Handed the bare config the writer still takes the samples and still writes
  /// the track, but the file's `esds` is then unparseable and every reader
  /// reports no sound at all — `MP4AudioESDS::Deserialize: the ES_Descriptor tag
  /// is incorrect` in the device log, an audio track count of zero in a test.
  private static func esds(wrapping config: Data) -> Data {
    /// One tag-and-length block, the length in the four-byte form a muxer
    /// writes, so a reader never has to guess how many bytes it is long.
    func block(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
      let size = body.count
      return [
        tag,
        0x80 | UInt8((size >> 21) & 0x7f),
        0x80 | UInt8((size >> 14) & 0x7f),
        0x80 | UInt8((size >> 7) & 0x7f),
        UInt8(size & 0x7f),
      ] + body
    }

    let decoder = block(0x04, [
      0x40,        // MPEG-4 audio
      0x15,        // a stream of its own, its own rate, the reserved bit
      0, 0, 0,     // a decoder buffer the file need not size
      0, 0, 0, 0,  // the highest bit rate, unknown
      0, 0, 0, 0,  // the average bit rate, unknown
    ] + block(0x05, [UInt8](config)))
    let stream = block(0x03, [0x00, 0x00, 0x00] + decoder + block(0x06, [0x02]))
    return Data(stream)
  }

  private static func audioDescription(_ config: TSAudioConfig) throws -> CMFormatDescription {
    var stream = AudioStreamBasicDescription(
      mSampleRate: Float64(config.sampleRate),
      mFormatID: kAudioFormatMPEG4AAC,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: 1024,
      mBytesPerFrame: 0,
      mChannelsPerFrame: UInt32(max(config.channels, 1)),
      mBitsPerChannel: 0,
      mReserved: 0
    )
    let cookie = [UInt8](esds(wrapping: config.magicCookie))
    var description: CMFormatDescription?

    let status = cookie.withUnsafeBufferPointer { bytes in
      CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &stream,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: cookie.count,
        magicCookie: bytes.baseAddress,
        extensions: nil,
        formatDescriptionOut: &description
      )
    }
    guard status == noErr, let description else { throw Failure.unusableAudio }
    return description
  }
}
