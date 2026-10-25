import AVFoundation
import SwiftUI
import UIKit

/// The video itself: a plain `AVPlayerLayer` host, because the chrome lives in
/// SwiftUI above it and `AVPlayerViewController`'s own chrome cannot be extended.
@MainActor
struct PlayerSurface: UIViewRepresentable {
  let player: AVPlayer
  let pictureInPicture: PictureInPicture
  let fit: VideoFit

  func makeUIView(context: Context) -> LayerHostView {
    let view = LayerHostView()
    view.backgroundColor = .black
    view.playerLayer.player = player
    view.playerLayer.videoGravity = fit.gravity
    pictureInPicture.attach(view.playerLayer)
    return view
  }

  func updateUIView(_ view: LayerHostView, context: Context) {
    if view.playerLayer.player !== player {
      view.playerLayer.player = player
      pictureInPicture.attach(view.playerLayer)
    }
    if view.playerLayer.videoGravity != fit.gravity {
      view.playerLayer.videoGravity = fit.gravity
    }
  }

  final class LayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
      // `layerClass` makes this the only kind of layer this view has.
      layer as! AVPlayerLayer
    }
  }
}
