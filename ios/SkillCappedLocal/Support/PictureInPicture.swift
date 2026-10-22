import AVFoundation
import AVKit
import Combine

/// Picture in picture for a hand-built player. `AVPlayerViewController` used to
/// give it for free, and the layer-backed controller brings it back: the same
/// capability, on a surface whose chrome is ours.
final class PictureInPicture: NSObject, ObservableObject {
  @Published private(set) var available = false
  @Published private(set) var active = false

  private var controller: AVPictureInPictureController?

  /// Called once the layer exists and has a player. Callbacks arrive on the main
  /// thread, which is the thread this object is used from.
  ///
  /// Stepping to the next lesson tears the surface down and builds a new one, so
  /// the controller is rebuilt around the new layer rather than left holding the
  /// one the old view took with it.
  func attach(_ layer: AVPlayerLayer) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    if let controller, controller.playerLayer === layer { return }
    guard let controller = AVPictureInPictureController(playerLayer: layer) else { return }
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    self.controller = controller
    available = true
  }

  func toggle() {
    guard let controller else { return }
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
    } else if controller.isPictureInPicturePossible {
      controller.startPictureInPicture()
    }
  }

  func detach() {
    controller?.delegate = nil
    controller = nil
    available = false
    active = false
  }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    active = true
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    active = false
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    active = false
  }
}
