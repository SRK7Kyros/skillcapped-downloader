import CoreGraphics
import Foundation

/// What a vertical drag on the player changes: the left half is the screen, the
/// right half is the sound.
enum PlayerChannel: Equatable {
  case brightness
  case volume
}

/// Double tapping a side adds five seconds per tap, and keeps adding: the second
/// double tap of a burst seeks 10 s, the third 15, and so on. A pause longer than
/// `window`, or a tap on the other side, starts the count again — otherwise a
/// person who tapped forward three times and then back once would be thrown 20 s
/// the wrong way.
struct SkipBurst: Equatable {
  static let step: Double = 5
  static let window: TimeInterval = 1.2

  private(set) var seconds: Double = 0
  private(set) var backward = false
  private var last: Date?

  /// Records one double tap and answers the seek it asks for, in seconds.
  mutating func tap(backward: Bool, at date: Date) -> Double {
    let stale = last.map { date.timeIntervalSince($0) > Self.window } ?? true
    if stale || backward != self.backward { seconds = 0 }
    self.backward = backward
    last = date
    seconds += Self.step
    return backward ? -seconds : seconds
  }

  mutating func reset() {
    seconds = 0
    last = nil
  }
}

/// Holding the picture runs it at double speed for as long as the finger stays
/// down, then hands back the rate it interrupted — including a pause, so holding
/// a stopped lesson previews it and lets go of it again.
struct HoldToSpeed: Equatable {
  static let factor: Float = 2

  /// The rate in force before the hold, or `nil` when nothing is held.
  private(set) var resuming: Float?

  var isHolding: Bool { resuming != nil }

  /// The rate to run while the picture is held. A second hold that starts before
  /// the first is released keeps the rate the first one remembers.
  mutating func begin(from rate: Float) -> Float {
    if resuming == nil { resuming = rate }
    return Self.factor
  }

  /// The rate to go back to, once: a release with nothing held answers `nil` and
  /// a second release cannot restore an older rate again.
  mutating func end() -> Float? {
    defer { resuming = nil }
    return resuming
  }
}

/// The maths behind the player's drags and its clock, kept out of the view so it
/// can be pinned by a test rather than by eye.
enum PlayerMath {
  /// Which half a drag began in.
  static func channel(x: CGFloat, width: CGFloat) -> PlayerChannel {
    x < width / 2 ? .brightness : .volume
  }

  /// A horizontal drag moves the playhead in proportion to the lesson: a drag
  /// across the whole width is the whole lesson.
  static func seek(from position: Double, translation: CGFloat, width: CGFloat, duration: Double) -> Double {
    guard duration.isFinite, duration > 0, width > 0 else { return max(0, position) }
    let start = position.isFinite ? position : 0
    return clamp(start + Double(translation / width) * duration, 0, duration)
  }

  /// A vertical drag changes a level: lifting the finger raises it, and dragging
  /// the whole height spans 0 to 1.
  static func level(from level: Double, translation: CGFloat, height: CGFloat) -> Double {
    guard height > 0, height.isFinite else { return clamp(level, 0, 1) }
    return clamp(level - Double(translation / height), 0, 1)
  }

  /// How much of the lesson is behind the playhead, 0…1.
  static func fraction(position: Double, duration: Double) -> CGFloat {
    guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
    return CGFloat(clamp(position / duration, 0, 1))
  }

  /// The playhead a tap at `x` on a bar `width` wide asks for.
  static func seconds(x: CGFloat, width: CGFloat, duration: Double) -> Double {
    guard width > 0, duration.isFinite, duration > 0 else { return 0 }
    return clamp(Double(min(max(x / width, 0), 1)) * duration, 0, duration)
  }

  static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(max(value, low), high)
  }

  /// `1:05`, `1:02:05`, and `--:--` before the duration is known.
  static func clock(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < 359_999 else { return "--:--" }
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remainder = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }
    return String(format: "%d:%02d", minutes, remainder)
  }
}
