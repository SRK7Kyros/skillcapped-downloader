import CoreGraphics
import UIKit

/// The shape of the glass the picture is shown in, which the chrome is placed
/// against.
///
/// Apple publishes no display corner radius, and the corners are not quarter
/// circles anyway: they are continuous curves — a superellipse whose exponent is
/// about five — so the glass bulges further into the corner than a circle of the
/// same radius and, in exchange, hugs the straight edges much more tightly.
/// Both halves matter to a control. The bulge is why a button can sit in a
/// corner at all; the hug is why a control near a corner needs *more* room than
/// one halfway up the edge, and a flat margin is what makes a corner button read
/// as sitting beside the corner instead of in it.
///
/// `pull(radius:distance:)` is the one rule the layout needs: at a height
/// `distance` from an edge, the glass has pulled this far in from the straight
/// edge, so a control that keeps the same air beside the glass as along it adds
/// that much to its own margin.
enum DisplayCorner {
  /// The exponent of an Apple display corner. Five is what the curve's outline
  /// is drawn with; two would be a plain circle, and the difference is visible
  /// exactly where the chrome sits — along the first forty points of an edge.
  static let exponent: CGFloat = 5

  /// The radii measured on the displays this app runs on, in points, keyed on
  /// the display's shorter side — the same number upright and held on its side.
  /// Two devices can share a size and a slightly different corner (an iPhone X
  /// is 39 where a 13 mini is 44); the newer shape wins.
  static let measured: [(short: CGFloat, radius: CGFloat)] = [
    (375, 44),  // iPhone 12/13 mini
    (390, 47.33),  // iPhone 12, 13, 14, 16e
    (393, 55),  // iPhone 15, 16
    (402, 62),  // iPhone 16 Pro, 17, 17 Pro
    (414, 41.5),  // iPhone XR, 11
    (428, 53.33),  // iPhone 12/13 Pro Max, 14 Plus
    (430, 55),  // iPhone 15 Plus, 16 Plus
    (440, 62),  // iPhone 16 Pro Max, 17 Pro Max
    (744, 18),  // iPad mini
    (820, 18),  // iPad 10.2"
    (834, 18),  // iPad Air, iPad Pro 11"
    (1024, 18),  // iPad 9.7", iPad Pro 12.9"
    (1194, 18),  // iPad Pro 13"
    (1366, 18),
  ]

  /// How far a display's short side may sit from a measured row and still take
  /// that row's corner — the window that absorbs a variant sized a fraction off
  /// the model it was measured on.
  static let tolerance: CGFloat = 2

  /// A display whose longer side is no longer than this is cut square to the
  /// corner — the SE family, the 8 and the iPod touch — whatever its width.
  static let squareBelow: CGFloat = 700

  /// The radius of a display of `size`, which is the display's own size and not
  /// a window's: a window on an iPad in Slide Over is square, a phone's glass is
  /// not.
  static func radius(for size: CGSize) -> CGFloat {
    let short = min(size.width, size.height)
    let long = max(size.width, size.height)
    guard short > 0, long > 0 else { return 0 }
    guard long > squareBelow else { return 0 }
    if let match = nearestMeasured(to: short) { return match.radius }
    // A display nobody measured: a phone rounds about a seventh of its width,
    // a pad far less, and neither reaches past what a hand-held device does.
    return short < squareBelow ? min(max(short * 0.14, 20), 62) : 18
  }

  /// The measured row closest to `short`, if one is within `tolerance`.
  ///
  /// The nearest row answers, never the first one inside the window: two
  /// displays can be two points apart on their short side and turn differently
  /// (428 is 53.33 where 430 is 55), so a first-match search handed the 430-wide
  /// phone its neighbour's corner.
  private static func nearestMeasured(to short: CGFloat) -> (short: CGFloat, radius: CGFloat)? {
    let closest = measured.min { abs($0.short - short) < abs($1.short - short) }
    guard let closest, abs(closest.short - short) <= tolerance else { return nil }
    return closest
  }

  /// How far the glass has pulled in from the straight edge, `distance` from the
  /// corner that edge turns on: the curve's own x for that y.
  ///
  /// Zero at the far end of the curve and the full radius at the edge itself.
  static func pull(radius: CGFloat, distance: CGFloat) -> CGFloat {
    guard radius > 0, distance < radius else { return 0 }
    let fromEdge = max(distance, 0)
    let t = (radius - fromEdge) / radius
    let inside = max(0, 1 - pow(t, exponent))
    return radius - radius * pow(inside, 1 / exponent)
  }

  /// Whether a point `x` and `y` from a corner is still on the glass: the
  /// superellipse's own test, which `clearance` solves on the diagonal.
  static func isInside(x: CGFloat, y: CGFloat, radius: CGFloat) -> Bool {
    guard radius > 0 else { return true }
    let dx = max(0, (radius - x) / radius)
    let dy = max(0, (radius - y) / radius)
    return pow(dx, exponent) + pow(dy, exponent) <= 1
  }

  /// The least a box's corner can sit from the two edges of a corner and still
  /// be off the glass: where the curve crosses the diagonal, which a
  /// superellipse reaches `2^(-1/n)` of the radius in from each edge — about an
  /// eighth on a phone, where a circle would take nearly a third.
  static func clearance(radius: CGFloat) -> CGFloat {
    guard radius > 0 else { return 0 }
    return radius * (1 - pow(2, -1 / exponent))
  }

  /// The radius of the display this build is running on. Read once: a display
  /// does not change shape while an app runs.
  @MainActor static var current: CGFloat {
    if let cached { return cached }
    let radius = live() ?? radius(for: displaySize)
    cached = radius
    return radius
  }

  @MainActor private static var cached: CGFloat?

  /// UIKit's own answer, asked for the way player apps have asked for years: the
  /// radius is a private property of the screen. Asked, never assumed — a UIKit
  /// that drops it answers nothing here instead of trapping, and the measured
  /// table covers every display the app has been run on.
  @MainActor private static func live() -> CGFloat? {
    guard let screen = activeScreen, screen.responds(to: NSSelectorFromString("_displayCornerRadius")),
      let number = screen.value(forKey: "_displayCornerRadius") as? NSNumber
    else { return nil }
    let radius = CGFloat(number.doubleValue)
    return radius > 0 && radius < 200 ? radius : nil
  }

  @MainActor private static var activeScreen: UIScreen? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .screen
  }

  @MainActor private static var displaySize: CGSize {
    activeScreen?.bounds.size ?? .zero
  }
}
