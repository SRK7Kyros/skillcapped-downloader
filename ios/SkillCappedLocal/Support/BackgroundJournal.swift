import Foundation

/// Keeps one short line per step the queue took while the screen was off.
///
/// A background download crosses a boundary the app cannot watch from a view: the
/// system owns the transfers, relaunches the app to hand one over, and suspends it
/// again. When a queue stalls the question is which of those actually happened, and
/// a device log answers that on a desk, not on a phone. Settings shows the last
/// lines, so a stall can be read where it happens.
final class BackgroundJournal: @unchecked Sendable {
  static let shared = BackgroundJournal()

  /// Several lessons of hand-overs, and still a rounding error in the container.
  static let limit = 240

  private static let clock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  static func line(at date: Date, event: String) -> String {
    "\(clock.string(from: date)) \(event)"
  }

  static func trim(_ lines: [String], to edge: Int = BackgroundJournal.limit) -> [String] {
    guard lines.count > edge else { return lines }
    return Array(lines.suffix(edge))
  }

  private let lock = NSLock()
  private let url: URL
  private var cache: [String]?

  init(url: URL? = nil) {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = url ?? base.appendingPathComponent("background-journal.txt")
  }

  func record(_ event: String) {
    lock.lock()
    defer { lock.unlock() }
    var lines = loaded()
    lines.append(Self.line(at: Date(), event: event))
    let kept = Self.trim(lines)
    cache = kept
    write(kept)
  }

  func lines(_ count: Int = 16) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(loaded().suffix(count))
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    cache = []
    write([])
  }

  private func loaded() -> [String] {
    if let cache { return cache }
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    cache = lines
    return lines
  }

  private func write(_ lines: [String]) {
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try? text.write(to: url, atomically: true, encoding: .utf8)
  }
}
