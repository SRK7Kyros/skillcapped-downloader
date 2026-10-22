import AVFoundation
import CryptoKit
import UIKit

/// Frames pulled out of the lessons themselves, so a library that never touches
/// the network still has real cover art. Results are cached in Caches/posters.
actor PosterStore {
  static let shared = PosterStore()

  private static let frameBudget: Double = 10

  private var memory: [String: UIImage] = [:]
  private var running: [String: Task<UIImage?, Never>] = [:]
  private let directory: URL

  init() {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    directory = caches.appendingPathComponent("posters", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func poster(for url: URL, width: CGFloat) async -> UIImage? {
    let key = cacheKey(url: url, width: width)
    if let cached = memory[key] { return cached }
    if let running = running[key] { return await running.value }

    let task = Task<UIImage?, Never> { [directory] in
      if let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".jpg")),
         let image = UIImage(data: data) {
        return image
      }
      guard let image = await PosterStore.frame(of: url, width: width) else { return nil }
      if let data = image.jpegData(compressionQuality: 0.8) {
        try? data.write(to: directory.appendingPathComponent(key + ".jpg"), options: .atomic)
      }
      return image
    }

    running[key] = task
    let image = await task.value
    running[key] = nil
    memory[key] = image
    return image
  }

  func forget() {
    memory.removeAll()
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private func cacheKey(url: URL, width: CGFloat) -> String {
    let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
    let raw = "\(url.path)|\(Int(stamp))|\(Int(width))"
    let digest = SHA256.hash(data: Data(raw.utf8))
    return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  /// Cover art, for the containers this platform can read a frame out of.
  ///
  /// A transport stream is served to the player as HLS, and an HLS asset reports no
  /// tracks — measured, the same stream that plays reports zero — so the generator
  /// has nothing to decode and never answers. The card keeps its gradient instead
  /// of paying for a request that cannot succeed.
  private static func frame(of url: URL, width: CGFloat) async -> UIImage? {
    guard !LessonServer.offers(url) else { return nil }
    let media = await LessonMedia.assets(url: url, seconds: 0)
    let asset = media ?? AVURLAsset(url: url)
    let seconds = await frameSecond(of: asset)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: max(width, 320), height: max(width, 320))
    generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    var frame = await oneFrame(from: generator, at: time)
    if frame == nil {
      frame = await oneFrame(from: generator, at: .zero)
    }
    return frame.map { UIImage(cgImage: $0) }
  }

  /// One frame, or nothing once the budget is spent. An HLS request can sit
  /// unanswered for good — measured in CI, where the same generator never returned
  /// — and the artwork is best effort, so the card draws its gradient instead of
  /// leaving a cell that waits forever.
  private static func oneFrame(from generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
    let promise = Promise<CGImage>()
    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, frame, _, _, _ in
      promise.resolve(frame)
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + frameBudget) { promise.resolve(nil) }
    return await promise.value
  }

  /// A frame a little way in, past title cards, capped so long lessons do not
  /// spend their first seconds on a fade.
  private static func frameSecond(of asset: AVAsset) async -> Double {
    guard let duration = try? await asset.load(.duration) else { return 3 }
    let total = CMTimeGetSeconds(duration)
    guard total.isFinite, total > 1, total != Double(LessonServer.unknownSeconds) else { return 3 }
    return min(20, max(1, total * 0.12))
  }
}

/// A single answer, from whichever finishes first, with the loser ignored.
private final class Promise<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var waiting: CheckedContinuation<T?, Never>?
  private var settled: T??

  func resolve(_ value: T?) {
    lock.lock()
    if let waiting {
      self.waiting = nil
      lock.unlock()
      waiting.resume(returning: value)
      return
    }
    if case .none = settled {
      settled = .some(value)
    }
    lock.unlock()
  }

  var value: T? {
    get async {
      await withCheckedContinuation { continuation in
        lock.lock()
        if let settled {
          lock.unlock()
          continuation.resume(returning: settled)
        } else {
          waiting = continuation
          lock.unlock()
        }
      }
    }
  }
}
