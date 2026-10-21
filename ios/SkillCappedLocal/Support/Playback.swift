import Foundation

/// Resume points, kept per file so a lesson picked up a week later carries on
/// where it stopped.
enum Playback {
  private static let prefix = "playback."

  static func saved(_ lesson: Lesson) -> Double {
    UserDefaults.standard.double(forKey: prefix + lesson.id)
  }

  static func save(_ seconds: Double, for lesson: Lesson) {
    guard seconds.isFinite, seconds > 0 else { return }
    UserDefaults.standard.set(seconds, forKey: prefix + lesson.id)
  }

  static func clear(for lesson: Lesson) {
    UserDefaults.standard.removeObject(forKey: prefix + lesson.id)
  }
}

/// One place that decides what is playing, so a row deep in a course can hand
/// the lesson to the full-screen player without every view owning a cover.
@MainActor
final class PlayerCoordinator: ObservableObject {
  @Published var lesson: Lesson?

  func play(_ lesson: Lesson) {
    self.lesson = lesson
  }

  func stop() {
    lesson = nil
  }
}
