import Foundation

/// How far into a lesson the viewer got. Keyed by the catalogue id when the file
/// carries one, so the same lesson keeps its place when it is re-downloaded at a
/// different quality or moved between library folders.
struct WatchProgress: Codable, Hashable {
  var position: Double
  var duration: Double
  var updatedAt: Date
  var completed: Bool
}

enum WatchProgressMath {
  /// A position within a second of the end is the end, not "almost finished".
  static let completeTail: Double = 15
  /// Anything under five seconds in is not worth resuming.
  static let resumeFloor: Double = 5

  static func fraction(position: Double, duration: Double) -> Double {
    guard duration > 0, position > 0 else { return 0 }
    return min(1, max(0, position / duration))
  }

  static func isComplete(position: Double, duration: Double) -> Bool {
    guard duration > 0 else { return false }
    return position >= duration - completeTail || fraction(position: position, duration: duration) >= 0.95
  }

  static func shouldResume(position: Double, duration: Double) -> Bool {
    guard position >= resumeFloor else { return false }
    return !isComplete(position: position, duration: duration)
  }
}

/// Watch positions, kept on disk so a lesson picked up a week later carries on
/// where it stopped.
@MainActor
final class ProgressStore: ObservableObject {
  @Published private(set) var entries: [String: WatchProgress] = [:]

  private let url = JSONFile.url("progress")
  private var saveTask: Task<Void, Never>?

  init() {
    if let saved = JSONFile.load([String: WatchProgress].self, from: url) {
      entries = saved
    }
  }

  func progress(for key: String) -> WatchProgress? { entries[key] }

  func fraction(for key: String) -> Double? {
    guard let entry = entries[key] else { return nil }
    return WatchProgressMath.fraction(position: entry.position, duration: entry.duration)
  }

  func isComplete(_ key: String) -> Bool { entries[key]?.completed ?? false }

  /// Called while playing and when leaving the player. A completed lesson keeps
  /// its end position so "watched" survives a relaunch.
  func record(key: String, position: Double, duration: Double) {
    guard !key.isEmpty else { return }
    guard position.isFinite, position > 0 else { return }
    let total = duration.isFinite && duration > 0 ? duration : (entries[key]?.duration ?? 0)
    let completed = WatchProgressMath.isComplete(position: position, duration: total) || (entries[key]?.completed ?? false)
    entries[key] = WatchProgress(position: position, duration: total, updatedAt: Date(), completed: completed)
    scheduleSave()
  }

  func markCompleted(key: String, duration: Double) {
    let total = duration > 0 ? duration : (entries[key]?.duration ?? 0)
    entries[key] = WatchProgress(position: total, duration: total, updatedAt: Date(), completed: true)
    scheduleSave()
  }

  func clear(key: String) {
    entries.removeValue(forKey: key)
    scheduleSave()
  }

  /// Keys with progress, most recently watched first — the continue-watching shelf.
  func recentKeys(limit: Int = 20) -> [String] {
    entries
      .filter { !$0.value.completed && $0.value.position >= WatchProgressMath.resumeFloor }
      .sorted { $0.value.updatedAt > $1.value.updatedAt }
      .prefix(limit)
      .map(\.key)
  }

  private func scheduleSave() {
    saveTask?.cancel()
    let snapshot = entries
    let target = url
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      JSONFile.save(snapshot, to: target)
    }
  }
}

extension Lesson {
  /// The catalogue id when the file carries one, so a lesson keeps its place
  /// after being re-downloaded or moved between library folders; the file path
  /// otherwise, which at least survives a relaunch.
  var progressKey: String { itemId ?? url.path }
}
