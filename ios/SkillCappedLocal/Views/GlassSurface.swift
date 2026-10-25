import SwiftUI

/// A sheet of the system's glass, drawn the way iOS 26 draws one: a blurred
/// backdrop that carries the picture's colour without its detail, a tint deep
/// enough that the glyphs on it stay readable over a bright frame, an edge lit
/// where the light would hit it and fading round the shape, a faint sheen across
/// the top of the material and a shade at its foot, and a shadow that lifts it
/// off the video.
///
/// The app runs on iOS 17, where `glassEffect` does not exist, so the material is
/// assembled by hand from a system material and five overlays. `Reduce
/// Transparency` swaps the whole thing for a flat fill, which is what that
/// setting asks for.
struct GlassSurface<S: InsettableShape>: ViewModifier {
  var shape: S
  /// How much of the picture the tint swallows. A bar over bright artwork takes
  /// more than a small button does, or the timeline would read through it.
  var tint: Double
  /// How bright the rim is on the lit edge.
  var rim: Double
  /// The rim's weight. A sheet the height of the transport's bar wears a heavier
  /// edge than a 32-point button does.
  var rimWidth: Double
  /// How far the surface sits off the picture.
  var lift: Double

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    content
      .background {
        if reduceTransparency {
          shape.fill(Palette.bg)
        } else {
          shape
            .fill(.regularMaterial)
            .overlay { shape.fill(Color.black.opacity(tint)) }
            .overlay {
              // Glass is lit along the edge facing the light and shaded where it
              // turns away, so the sheet reads as a slab rather than a flat
              // panel of grey.
              shape.fill(
                LinearGradient(
                  stops: [
                    .init(color: .white.opacity(0.20), location: 0),
                    .init(color: .white.opacity(0.06), location: 0.34),
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.16), location: 1),
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
            }
        }
      }
      .overlay {
        // The rim: bright where the light lands on the edge, fading round the
        // shape so it never draws a uniform outline.
        shape.strokeBorder(
          LinearGradient(
            stops: [
              .init(color: .white.opacity(rim), location: 0),
              .init(color: .white.opacity(rim * 0.5), location: 0.45),
              .init(color: .white.opacity(rim * 0.2), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: rimWidth
        )
      }
      .overlay {
        // A dark hairline outside the rim, which is what gives a sheet of glass
        // an edge of its own against a bright frame.
        shape.strokeBorder(Color.black.opacity(0.42), lineWidth: 0.5)
      }
      .compositingGroup()
      .shadow(color: .black.opacity(lift), radius: 18, y: 6)
  }
}

extension View {
  /// Draws this view on a sheet of glass — see `GlassSurface`.
  func glass<S: InsettableShape>(
    _ shape: S,
    tint: Double = 0.42,
    rim: Double = 0.56,
    rimWidth: Double = 1,
    lift: Double = 0.36
  ) -> some View {
    modifier(GlassSurface(shape: shape, tint: tint, rim: rim, rimWidth: rimWidth, lift: lift))
  }
}
