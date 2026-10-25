import AVFoundation

/// How the picture fills the window: the whole frame with whatever bars its
/// shape needs, or the window filled edge to edge by cropping the overflow.
///
/// The two are not the same picture. A lesson is 16:9 and a phone on its side is
/// wider still, so *fit* letterboxes it — the whole frame, black at the sides —
/// while *fill* crops its top and bottom instead. Every phone player offers both
/// because neither suits every lesson: a rune page wants the edges of the screen,
/// a wide team fight wants the frame it was shot in.
enum VideoFit: String, Codable, CaseIterable {
  /// The whole frame, bars where the shapes disagree.
  case fit
  /// The window filled, the overflow cropped.
  case fill

  /// What the layer draws with.
  var gravity: AVVideoGravity {
    switch self {
    case .fit: return .resizeAspect
    case .fill: return .resizeAspectFill
    }
  }

  /// The other one, which is what tapping the control asks for.
  var toggled: VideoFit {
    self == .fit ? .fill : .fit
  }

  /// The glyph shows the shape the button moves to, the way a player's own
  /// expand control does: arrows out while the picture could fill more of the
  /// screen, arrows in while it can be brought back whole.
  var glyph: String {
    switch self {
    case .fit: return "arrow.up.left.and.arrow.down.right"
    case .fill: return "arrow.down.right.and.arrow.up.left"
    }
  }

  /// What tapping does. A screen reader hears the action, not the state.
  var actionLabel: String {
    switch self {
    case .fit: return "Fill the screen"
    case .fill: return "Fit the whole video"
    }
  }
}
