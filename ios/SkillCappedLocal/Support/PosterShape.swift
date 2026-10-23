import CoreGraphics

/// The shape of a media box. A course's art is a 576×912 portrait card with the
/// title baked into the top; a lesson still is 1920×1080.
///
/// A box is drawn at **one window shape** — the shape a grid was designed around
/// — never at the shape of whichever picture happened to arrive. The art fills
/// that window and is anchored at the top, so a poster that is a little taller
/// loses its bottom (the site's baked-in title lives at the top and always
/// survives) while a shorter one is trimmed at the sides. That is what keeps
/// every card in a row exactly the same height, and it is also why a grid never
/// reflows when the art finishes loading.
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

  /// The shape a box is drawn at: its window when it has one, so a picture can
  /// never change the box; otherwise the picture's own shape, then the stand-in.
  static func window(art: CGFloat?, fallback: CGFloat, window: CGFloat?) -> CGFloat {
    if let window, window.isFinite, window > 0 { return window }
    if let art, art.isFinite, art > 0 { return art }
    return fallback
  }

  /// The size the art is drawn at to cover a box of `size` without distortion:
  /// the larger dimension matches, the other overflows. Callers anchor the
  /// overflow at the **top**, so a too-tall poster is cropped from its bottom.
  static func fill(size: CGSize, art: CGFloat) -> CGSize {
    guard size.width > 0, size.height > 0, art.isFinite, art > 0 else { return size }
    let box = size.width / size.height
    if art > box { return CGSize(width: size.height * art, height: size.height) }
    return CGSize(width: size.width, height: size.width / art)
  }
}
