import Foundation

/// The two facts a queue row carries besides its picture and its name: how long
/// the lesson runs, and how far into it the viewer got. Kept out of the view so
/// the wording can be pinned without driving a player.
enum PlayerQueueSummary {
  /// "Watched 42% · 12:40", or the length alone before the lesson is started.
  static func detail(seconds: Int, watched: Double?) -> String {
    let length = Format.clock(seconds)
    guard let watched, watched.isFinite, watched > 0.005 else { return length }
    let share = min(max(watched, 0), 1)
    if share >= 0.995 { return "Watched · \(length)" }
    return "Watched \(Int((share * 100).rounded()))% · \(length)"
  }

  /// "2 of 7" — where the lesson on screen sits in the list it was opened from.
  /// Nothing for a queue of one, which is a number that answers no question.
  static func position(of id: String, in queue: [Lesson]) -> String? {
    guard queue.count > 1, let index = queue.firstIndex(where: { $0.id == id }) else { return nil }
    return "\(index + 1) of \(queue.count)"
  }
}
