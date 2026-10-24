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

    var audio: AVAssetWriterInput?
    if let audioFormat {
      let input = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: nil,
        sourceFormatHint: audioFormat
      )
      input.expectsMediaDataInRealTime = false
      // Only a video track takes a media time scale: asking an audio one for a
      // non-default value raises, which is how this was learned.
      guard writer.canAdd(input) else { throw Failure.unusableAudio }
      writer.add(input)
      audio = input
    }

    guard writer.startWriting() else {
      throw Failure.writer(writer.error?.localizedDescription ?? "the writer did not start")
    }
    writer.startSession(atSourceTime: .zero)

    /// The frame waiting for the next one, because a sample's duration is the gap
    /// to its successor and the last one has none.
    var pending: (payload: Data, pts: Int64, dts: Int64, sync: Bool)?
    var lastTicks: Int64 = 3_000
    var end: Int64 = 0
    var failure: Error?

    let demuxer = TSDemuxer()
    var fedVideo = 0
    var fedAudio = 0
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
            try feed(
              video,
              into: writer,
              payload: previous.payload,
              format: videoFormat,
              pts: previous.pts,
              dts: previous.dts,
              duration: CMTime(value: ticks, timescale: CMTimeScale(TSDemuxer.clock)),
              sync: previous.sync
            )
            fedVideo += 1
          }
          pending = (sample.payload, pts, dts, sample.isSync)
          end = max(end, pts)

        case .audio:
          guard let audio, let audioFormat else { return }
          try feed(
            audio,
            into: writer,
            payload: sample.payload,
            format: audioFormat,
            pts: pts,
            dts: pts,
            duration: audioFrame,
            sync: true
          )
          fedAudio += 1
          end = max(end, pts)
        }
      } catch {
        if let named = error as? Failure, case let .writer(reason) = named {
          let picture = video.isReadyForMoreMediaData ? "ready" : "blocked"
          let sound = audio.map { $0.isReadyForMoreMediaData ? "ready" : "blocked" } ?? "absent"
          failure = Failure.writer(
            "\(reason) — after \(fedVideo) picture and \(fedAudio) sound samples; "
              + "picture \(picture), sound \(sound)"
          )
        } else {
          failure = error
        }
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
        try feed(
          video,
          into: writer,
          payload: previous.payload,
          format: videoFormat,
          pts: previous.pts,
          dts: previous.dts,
          duration: CMTime(value: lastTicks, timescale: CMTimeScale(TSDemuxer.clock)),
          sync: previous.sync
        )
        pending = nil
        end = max(end, previous.pts + lastTicks)
      }
    } catch {
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: destination)
      throw error
    }

    video.markAsFinished()
    audio?.markAsFinished()

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

  // MARK: - Samples

  private static func feed(
    _ input: AVAssetWriterInput,
    into writer: AVAssetWriter,
    payload: Data,
    format: CMFormatDescription,
    pts: Int64,
    dts: Int64,
    duration: CMTime,
    sync: Bool
  ) throws {
    // A writer that has failed never asks for more data, so the wait has to end
    // and the reason has to carry what the writer said rather than a shrug.
    var waited = 0.0
    while !input.isReadyForMoreMediaData {
      if let reason = writer.error {
        throw Failure.writer("the \(input.mediaType.rawValue) track was refused: \(reason.localizedDescription)")
      }
      guard waited < 5 else {
        throw Failure.writer(
          "the \(input.mediaType.rawValue) track stopped accepting data (writer status \(writer.status.rawValue))"
        )
      }
      Thread.sleep(forTimeInterval: 0.004)
      waited += 0.004
    }

    let buffer = try sampleBuffer(
      payload,
      format: format,
      pts: CMTime(value: pts, timescale: CMTimeScale(TSDemuxer.clock)),
      dts: CMTime(value: dts, timescale: CMTimeScale(TSDemuxer.clock)),
      duration: duration,
      sync: sync
    )
    guard input.append(buffer) else {
      throw Failure.writer(writer.error?.localizedDescription ?? "a sample was refused")
    }
  }

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
    let cookie = [UInt8](config.magicCookie)
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
