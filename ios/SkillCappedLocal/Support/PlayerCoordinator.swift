import Foundation

/// One place that decides what is playing, so a row deep in a course can hand
/// the lesson to the full-screen player without every view owning a cover.
@MainActor
final class PlayerCoordinator: ObservableObject {
  @Published var lesson: Lesson?
  /// The list the played lesson came from, so the transport can step through it.
  @Published private(set) var queue: [Lesson] = []

  func play(_ lesson: Lesson, in lessons: [Lesson] = []) {
    queue = lessons.contains(where: { $0.id == lesson.id }) ? lessons : [lesson]
    self.lesson = lesson
  }

  /// The lesson before or after this one in the queue it was opened from.
  func neighbour(of lesson: Lesson, forward: Bool) -> Lesson? {
    guard queue.count > 1, let index = queue.firstIndex(where: { $0.id == lesson.id }) else {
      return nil
    }
    let step = forward ? index + 1 : index - 1
    guard queue.indices.contains(step) else { return nil }
    return queue[step]
  }

  func stop() {
    lesson = nil
    queue = []
  }
}
