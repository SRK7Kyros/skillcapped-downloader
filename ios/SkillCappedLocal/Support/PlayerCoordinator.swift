import Foundation

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
