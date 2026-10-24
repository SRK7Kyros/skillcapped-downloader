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

  /// The air kept beside a control on top of the safe area it has to clear. The
  /// insets carry the island, the home indicator and the corners a phone turns
  /// on its side; this is the little more that stops a control from reading as
  /// clipped by the screen's own shape or as touching its edge.
  static let edgeMargin: CGFloat = 12

  /// How far a control sits from the window's edge. Portrait has no side inset,
  /// so a phone upright keeps its margin; on its side the chrome clears the
  /// corner it turned, and the bar and the header agree, which is what makes the
  /// transport read as centred in the picture rather than in the glass.
  static func edge(inset: CGFloat) -> CGFloat {
    inset + edgeMargin
  }
}
