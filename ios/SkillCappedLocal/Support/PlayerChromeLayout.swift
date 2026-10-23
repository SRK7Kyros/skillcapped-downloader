import CoreGraphics

/// Geometry the transport's two shapes share, kept out of the view so a test can
/// pin it: every control in one row when the window is wide, and the three that
/// are touched least often floating above the bar when it is not.
enum PlayerChromeLayout {
  /// Below this width a phone cannot hold the whole transport *and* both times
  /// in one row, so the rate and the two queue steps leave the bar — which is
  /// also what buys the timeline the width to show its readouts. A portrait
  /// phone (320–430) and an iPad in a narrow split both fall here; a phone on
  /// its side (667+) and a whole iPad do not.
  static let floatingBelow: CGFloat = 540

  /// Whether the rate and the two queue steps float above the bar. An unknown
  /// width is not a narrow window, so it keeps the single row.
  static func floatsControls(width: CGFloat) -> Bool {
    width > 0 && width < floatingBelow
  }
}
