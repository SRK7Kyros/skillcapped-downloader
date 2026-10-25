import SwiftUI

/// A sheet of the system's glass, drawn the way iOS 26 draws one: a blurred
/// backdrop deep enough that the glyphs on it stay readable over a bright frame,
/// a specular bloom where the light lands on it, an edge lit all the way round
/// the shape — brightest where the light hits, lifting again where the picture
/// shines through at the foot — a hair of light and a hair of shade just inside
/// that edge, and a shadow that lifts it off the video.
///
/// The app runs on iOS 17, where `glassEffect` does not exist, so the material is
/// assembled by hand: a system material, a tint, a sheen, a bloom, a rim, two
/// inner hairlines and an outer one. `Reduce Transparency` swaps the whole thing
/// for a flat fill, which is what that setting asks for.
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
      .background { backdrop }
      .overlay { bloom }
      .overlay { rimLight }
      .overlay { lens }
      .overlay {
        // A dark hairline outside the rim, which is what gives a sheet of glass
        // an edge of its own against a bright frame.
        shape.strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5)
      }
      .compositingGroup()
      .shadow(color: .black.opacity(lift), radius: 22, y: 8)
      .shadow(color: .black.opacity(lift * 0.7), radius: 3, y: 1)
  }

  @ViewBuilder
  private var backdrop: some View {
    if reduceTransparency {
      shape.fill(Palette.bg)
    } else {
      shape
        .fill(.regularMaterial)
        .overlay { shape.fill(Color.black.opacity(tint)) }
        .overlay {
          // Glass is lit along the edge facing the light and shaded where it
          // turns away, so the sheet reads as a slab rather than a flat panel.
          shape.fill(
            LinearGradient(
              stops: [
                .init(color: .white.opacity(0.24), location: 0),
                .init(color: .white.opacity(0.06), location: 0.28),
                .init(color: .clear, location: 0.58),
                .init(color: .black.opacity(0.10), location: 0.82),
                .init(color: .black.opacity(0.24), location: 1),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
        }
    }
  }

  /// The highlight a sheet of glass picks up where the light falls on it: a wide,
  /// soft bloom in the leading corner, never a spot in the middle — which is what
  /// reads as a reflection rather than a gradient.
  private var bloom: some View {
    GeometryReader { geo in
      shape.fill(
        RadialGradient(
          stops: [
            .init(color: .white.opacity(reduceTransparency ? 0 : 0.26), location: 0),
            .init(color: .white.opacity(reduceTransparency ? 0 : 0.07), location: 0.34),
            .init(color: .clear, location: 0.74),
          ],
          center: UnitPoint(x: 0.2, y: 0.02),
          startRadius: 0,
          endRadius: max(geo.size.width, geo.size.height) * 0.92
        )
      )
    }
    .allowsHitTesting(false)
  }

  /// The edge itself: lit round the whole shape, so the glass keeps a rim where a
  /// single direction gradient would leave a flat side.
  private var rimLight: some View {
    shape.strokeBorder(
      AngularGradient(
        gradient: Gradient(stops: [
          .init(color: .white.opacity(rim), location: 0.00),
          .init(color: .white.opacity(rim * 0.55), location: 0.14),
          .init(color: .white.opacity(rim * 0.14), location: 0.38),
          .init(color: .white.opacity(rim * 0.06), location: 0.55),
          .init(color: .white.opacity(rim * 0.30), location: 0.80),
          .init(color: .white.opacity(rim * 0.80), location: 0.94),
          .init(color: .white.opacity(rim), location: 1.00),
        ]),
        center: .center,
        startAngle: .degrees(-150),
        endAngle: .degrees(210)
      ),
      lineWidth: rimWidth
    )
    .allowsHitTesting(false)
  }

  /// The thickness of the slab: a hair of light just inside the rim, then a hair
  /// of shade — which is what stops an edge reading as a drawn outline.
  private var lens: some View {
    ZStack {
      shape.inset(by: rimWidth).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
      shape.inset(by: rimWidth + 1.2).strokeBorder(Color.black.opacity(0.16), lineWidth: 0.8)
    }
    .allowsHitTesting(false)
  }
}

extension View {
  /// Draws this view on a sheet of glass — see `GlassSurface`.
  func glass<S: InsettableShape>(
    _ shape: S,
    tint: Double = 0.5,
    rim: Double = 0.6,
    rimWidth: Double = 1,
    lift: Double = 0.36
  ) -> some View {
    modifier(GlassSurface(shape: shape, tint: tint, rim: rim, rimWidth: rimWidth, lift: lift))
  }
}
