import CoreGraphics
import SwiftUI

/// The maths behind pinching the picture: how far it may zoom, and where it has
/// to move so the spot under the fingers stays under them.
enum PlayerZoom {
  static let minScale: CGFloat = 1
  static let maxScale: CGFloat = 5

  /// How much bigger the picture may be drawn. A pinch below fit and above five
  /// times is clamped rather than refused, so the fingers keep their grip.
  static func clampScale(_ scale: CGFloat) -> CGFloat {
    guard scale.isFinite else { return minScale }
    return min(max(scale, minScale), maxScale)
  }

  /// The offset that keeps the point under `anchor` where it was while the picture
  /// grows from `from` to `to`, in the window `size` wide.
  ///
  /// The picture is drawn about its own centre, so a content point `p` lands at
  /// `c + scale·(p − c) + offset`. Holding the anchor's content point still gives
  /// `offset = offset₀·(to/from) + (anchor − centre)·(1 − to/from)` — the pinch
  /// grows the picture around the fingers instead of the middle of the screen.
  static func offset(
    starting offset: CGSize,
    from: CGFloat,
    to: CGFloat,
    anchor: UnitPoint,
    size: CGSize
  ) -> CGSize {
    guard from > 0, to > 0, from.isFinite, to.isFinite else { return offset }
    let growth = to / from
    let pinned = CGSize(
      width: (anchor.x - 0.5) * size.width,
      height: (anchor.y - 0.5) * size.height
    )
    return clamped(
      CGSize(
        width: offset.width * growth + pinned.width * (1 - growth),
        height: offset.height * growth + pinned.height * (1 - growth)
      ),
      scale: to,
      size: size
    )
  }

  /// How far a zoomed picture may be dragged. Past this its own edge would come
  /// inside the window and a band of black would show beside it.
  static func clamped(_ offset: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
    let zoom = clampScale(scale)
    let reach = CGSize(
      width: max(0, (zoom - 1) * size.width / 2),
      height: max(0, (zoom - 1) * size.height / 2)
    )
    return CGSize(
      width: min(max(offset.width, -reach.width), reach.width),
      height: min(max(offset.height, -reach.height), reach.height)
    )
  }
}
