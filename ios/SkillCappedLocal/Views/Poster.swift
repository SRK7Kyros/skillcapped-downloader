import SwiftUI
import UIKit

/// A frame taken from the lesson itself, with a deterministic gradient behind it
/// while the frame is being pulled (or when the file cannot produce one).
struct Poster: View {
  let url: URL?
  var seed: String
  var targetWidth: CGFloat = 700

  @State private var image: UIImage?

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        LinearGradient(
          colors: Palette.gradient(for: seed),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        } else {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white.opacity(0.22))
        }
      }
    }
    .clipped()
    .task(id: url) {
      guard let url else {
        image = nil
        return
      }
      image = await PosterStore.shared.poster(for: url, width: targetWidth)
    }
  }
}
