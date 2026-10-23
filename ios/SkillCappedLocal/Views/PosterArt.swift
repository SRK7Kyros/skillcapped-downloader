import SwiftUI
import UIKit

/// One media box, whether its art is a frame pulled out of a local file or a
/// poster the site hosts.
///
/// A box is drawn at **one window shape** — the shape its grid was designed
/// around — never at the shape of whichever picture happened to arrive. The art
/// fills that window and is anchored at the top, so a poster that is a little
/// taller loses its bottom (the title the site bakes into the top always
/// survives) and a wider one is trimmed at the sides. That is what keeps every
/// card in a row exactly the same height, and it is also why a grid never
/// reflows when the art finishes loading.
///
/// `window == nil` keeps the older behaviour: the box takes the art's own shape,
/// for a one-off hero or a thumbnail inside a row.
struct PosterArt: View {
  let url: URL?
  var seed: String
  /// A hosted poster to fall back to when the local file cannot yield a frame —
  /// which is every transport stream, since iOS will not decode one.
  var remote: URL?
  /// Shape before the art loads, and the shape kept when no window is given.
  var fallback: CGFloat = PosterShape.landscape
  /// The one shape every box in this grid is drawn at. A window is what makes a
  /// row of cards uniform whatever art each one got.
  var window: CGFloat?
  /// A fixed width for a box inside a row; `nil` takes the width it is offered
  /// and keeps its shape at whatever height that needs.
  var width: CGFloat?
  /// How wide a local frame is generated, in points.
  var targetWidth: CGFloat = 700
  var glyphSize: CGFloat = 28

  @State private var image: UIImage?
  @State private var shape: CGFloat?

  private var ratio: CGFloat {
    PosterShape.window(art: shape, fallback: fallback, window: window)
  }

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
      .task(id: "\(url?.absoluteString ?? "")|\(remote?.absoluteString ?? "")") { await load() }
  }

  /// A box of the window's shape — the width the caller pins, or the width the
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
      if window == nil {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        GeometryReader { geo in
          let artRatio = PosterShape.ratio(of: image.size) ?? ratio
          let draw = PosterShape.fill(size: geo.size, art: artRatio)
          Image(uiImage: image)
            .resizable()
            .frame(width: draw.width, height: draw.height)
            // Top-anchored: the overflow inside a window is only ever at the
            // bottom, and sideways overflow stays centred.
            .position(x: geo.size.width / 2, y: draw.height / 2)
        }
      }
    } else {
      Image(systemName: "play.circle.fill")
        .font(.system(size: glyphSize, weight: .semibold))
        .foregroundStyle(.white.opacity(0.22))
    }
  }

  private func load() async {
    var loaded: UIImage?
    if let url {
      loaded = url.isFileURL
        ? await PosterStore.shared.poster(for: url, width: targetWidth)
        : await RemoteArtStore.shared.image(for: url)
    }
    if loaded == nil, let remote {
      loaded = await RemoteArtStore.shared.image(for: remote)
    }
    guard !Task.isCancelled else { return }
    image = loaded
    shape = loaded.flatMap { PosterShape.ratio(of: $0.size) }
  }
}
