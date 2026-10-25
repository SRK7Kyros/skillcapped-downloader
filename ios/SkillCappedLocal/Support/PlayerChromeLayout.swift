import CoreGraphics

/// Geometry the transport's two shapes share, kept out of the view so a test can
/// pin it: every control in one row when the window is wide, and the three that
/// are touched least often floating above the bar when it is not.
///
/// The chrome floats over the picture rather than sitting in a toolbar, so it is
/// placed against the display's own corner (`DisplayCorner`) instead of against
/// the safe area alone. The insets a phone reports on its side belong to the
/// island, which sits halfway along an edge; the header and the bar run along the
/// edges the island does *not* sit on, and adding the island's inset to them was
/// what pushed the whole transport into the middle of the picture and left the
/// corners empty.
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

  /// The air kept between the chrome and the glass where no corner turns.
  static let edgeMargin: CGFloat = 14

  /// How far a row of chrome sits from the edge it is nearest: as far as the
  /// system says something lives there — the island, a status bar, the home
  /// indicator — and never less than the margin.
  static func away(safe: CGFloat) -> CGFloat {
    max(safe, edgeMargin)
  }

  /// How far a row of chrome sits from the glass sideways.
  ///
  /// A row beside a corner keeps the same air to the glass as it keeps to the
  /// edge above or below it, and the glass has already pulled in
  /// `DisplayCorner.pull` at that height — so that much is added to the margin.
  /// The result is a control that sits *in* the corner rather than beside it,
  /// which is what a rounded display asks for.
  static func side(radius: CGFloat, fromCorner distance: CGFloat) -> CGFloat {
    DisplayCorner.pull(radius: radius, distance: distance) + edgeMargin
  }
}
