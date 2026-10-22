import CoreGraphics

/// The shape of a media box. A course's art is a 576×912 portrait card with the
/// title baked into the top; a lesson still is 1920×1080. The box takes the
/// art's own shape once the art has loaded — never a house ratio the art was not
/// drawn at — and stands in with the shape that kind of art usually has until
/// then, so a grid never reflows under the tap.
enum PosterShape {
  /// 576 / 912: the SkillCapped course card, portrait.
  static let portrait: CGFloat = 576.0 / 912.0
  /// 16 / 9: a video still.
  static let landscape: CGFloat = 16.0 / 9.0

  static func fallback(course: Bool) -> CGFloat { course ? portrait : landscape }

  /// Width over height, or nil when the size cannot describe a box.
  static func ratio(width: CGFloat, height: CGFloat) -> CGFloat? {
    guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
    return width / height
  }

  static func ratio(of size: CGSize) -> CGFloat? {
    ratio(width: size.width, height: size.height)
  }

  /// The height a box this wide needs to keep its shape.
  static func height(width: CGFloat, ratio: CGFloat) -> CGFloat {
    guard width.isFinite, width > 0, ratio.isFinite, ratio > 0 else { return 0 }
    return width / ratio
  }
}
