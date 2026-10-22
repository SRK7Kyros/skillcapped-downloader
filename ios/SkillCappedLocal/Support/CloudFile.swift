import Foundation

/// iCloud Drive hands the app *placeholders*, not bytes. `AVPlayer` cannot open
/// one, so playback asks iCloud for the file and waits for it to land.
///
/// Only reading is affected: scanning a folder never downloads anything (a
/// directory listing and a file's size are metadata), and cover art falls back to
/// the gradient when a frame cannot be read from a placeholder.
enum CloudFile {
  /// True when `url` lives in iCloud Drive and this device does not hold the
  /// current version of its bytes.
  static func needsDownload(_ url: URL, manager: FileManager = .default) -> Bool {
    let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return false }
    return needsDownload(isUbiquitous: values.isUbiquitousItem, status: values.ubiquitousItemDownloadingStatus)
  }

  /// The rule on its own, so it can be tested without a real iCloud container.
  /// `.downloaded` still counts: it means an older version is here and the
  /// current one is not.
  static func needsDownload(isUbiquitous: Bool?, status: URLUbiquitousItemDownloadingStatus?) -> Bool {
    guard isUbiquitous == true else { return false }
    return status != .current
  }

  /// Ask iCloud for the bytes. Asking twice is harmless.
  @discardableResult
  static func request(_ url: URL, manager: FileManager = .default) -> Bool {
    if (try? manager.startDownloadingUbiquitousItem(at: url)) != nil { return true }
    return !needsDownload(url, manager: manager)
  }

  /// Wait until the file is local. Cancelling the surrounding task stops the
  /// wait — iCloud keeps the download going, so a second attempt finishes sooner.
  static func waitUntilLocal(
    _ url: URL,
    manager: FileManager = .default,
    interval: Duration = .milliseconds(400)
  ) async -> Bool {
    if !needsDownload(url, manager: manager) { return true }
    request(url, manager: manager)
    while !Task.isCancelled {
      if !needsDownload(url, manager: manager) { return true }
      try? await Task.sleep(for: interval)
    }
    return !needsDownload(url, manager: manager)
  }
}
