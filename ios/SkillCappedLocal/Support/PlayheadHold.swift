import Foundation

/// Whether the scrubber follows the player's clock, or stands on the position a
/// finger (or a seek on its way there) put it on.
///
/// A seek is asynchronous: `AVPlayer.currentTime()` keeps answering the position
/// the seek left behind until it lands, and the quarters-of-a-second ticks that
/// arrive meanwhile carry that old position. Writing them into the bar is what
/// made it snap back to where a scrub began and jump forward again a beat later,
/// so the bar holds the target until the player's own clock agrees with it.
struct PlayheadHold {
  /// How close a clock reading has to be to the target to count as arrived. A
  /// zero-tolerance seek lands exactly, so this only has to absorb the clock's
  /// own drift — generous enough not to miss, tight enough not to accept the
  /// position the seek left.
  static let landed: Double = 0.5

  /// A finger is choosing a position: the bar belongs to the finger.
  private(set) var choosing = false
  /// The position a seek is heading for, until the clock reports it.
  private(set) var landing: Double?

  /// Whether the bar stands on a held position rather than the clock's.
  var isHeld: Bool { choosing || landing != nil }

  /// A finger chose a position; it outranks any seek still on its way.
  mutating func choose() {
    choosing = true
    landing = nil
  }

  /// A seek is on its way: the finger has let go.
  mutating func seek(_ target: Double) {
    choosing = false
    landing = target
  }

  /// The hold on `target` ran out. A seek that never landed must not leave the
  /// bar standing on a position the picture is not on.
  mutating func expire(_ target: Double) {
    if landing == target { landing = nil }
  }

  /// The position the bar should show for a clock reading, or `nil` while it
  /// stands still on a held one.
  mutating func follow(_ seconds: Double) -> Double? {
    guard !choosing, seconds.isFinite else { return nil }
    if let target = landing {
      guard abs(seconds - target) <= Self.landed else { return nil }
      landing = nil
    }
    return seconds
  }
}
