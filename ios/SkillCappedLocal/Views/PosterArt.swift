import SwiftUI
import UIKit

/// One media box, whether its art is a frame pulled out of a local file or a
/// poster the site hosts.
///
/// The box takes the art's own shape — a 576×912 course card, a 1920×1080 still —
/// because cropping a portrait poster into a 16:9 strip throws away two thirds of
/// it, including the title the site baked into the top. Before the art arrives
/// the box stands in with the shape that kind of art usually has, so a grid does
/// not reflow under the tap.
struct PosterArt: View {
  let url: URL?
  var seed: String
  /// Shape before the art loads: `PosterShape.portrait` for a course card,
  /// `PosterShape.landscape` for a lesson.
  var fallback: CGFloat = PosterShape.landscape
  /// A fixed width for a box inside a row; `nil` takes the width it is offered
  /// and keeps its shape at whatever height that needs.
  var width: CGFloat?
  /// How wide a local frame is generated, in points.
  var targetWidth: CGFloat = 700
  var glyphSize: CGFloat = 28

  @State private var image: UIImage?
  @State private var shape: CGFloat?

  private var ratio: CGFloat { shape ?? fallback }

  var body: some View {
    box
      .overlay { art }
      .background(
        LinearGradient(
          colors: Palette.gradient(for: seed),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .clipped()
      .task(id: url) { await load() }
  }

  /// A box of the art's own shape — the width the caller pins, or the width the
  /// parent offers with the height that shape needs.
  @ViewBuilder
  private var box: some View {
    if let width {
      Color.clear
        .frame(width: width, height: PosterShape.height(width: width, ratio: ratio))
    } else {
      Color.clear
        .aspectRatio(ratio, contentMode: .fit)
    }
  }

  @ViewBuilder
  private var art: some View {
    if let image {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      Image(systemName: "play.circle.fill")
        .font(.system(size: glyphSize, weight: .semibold))
        .foregroundStyle(.white.opacity(0.22))
    }
  }

  private func load() async {
    guard let url else {
      image = nil
      shape = nil
      return
    }
    let loaded: UIImage?
    if url.isFileURL {
      loaded = await PosterStore.shared.poster(for: url, width: targetWidth)
    } else {
      loaded = await RemoteArtStore.shared.image(for: url)
    }
    guard !Task.isCancelled else { return }
    image = loaded
    shape = loaded.flatMap { PosterShape.ratio(of: $0.size) }
  }
}
