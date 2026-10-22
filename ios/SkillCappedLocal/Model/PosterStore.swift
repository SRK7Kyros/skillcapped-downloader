import AVFoundation
import CryptoKit
import UIKit

/// Frames pulled out of the lessons themselves, so a library that never touches
/// the network still has real cover art. Results are cached in Caches/posters.
actor PosterStore {
  static let shared = PosterStore()

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

  private static func frame(of url: URL, width: CGFloat) async -> UIImage? {
    let media = LessonMedia.assets(url: url, seconds: 0)
    let asset = media?.asset ?? AVURLAsset(url: url)
    let seconds = await frameSecond(of: asset)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: max(width, 320), height: max(width, 320))
    generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    let frame = (try? await generator.image(at: time)) ?? (try? await generator.image(at: .zero))
    _ = media?.loader
    guard let frame else { return nil }
    return UIImage(cgImage: frame.image)
  }

  /// A frame a little way in, past title cards, capped so long lessons do not
  /// spend their first seconds on a fade.
  private static func frameSecond(of asset: AVAsset) async -> Double {
    guard let duration = try? await asset.load(.duration) else { return 3 }
    let total = CMTimeGetSeconds(duration)
    guard total.isFinite, total > 1 else { return 0 }
    return min(20, max(1, total * 0.12))
  }
}
