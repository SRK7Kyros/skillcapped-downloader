import AVFoundation
import MediaPlayer
import UIKit

/// The system output volume, which iOS otherwise only lets a person change with
/// the hardware buttons: `AVAudioSession.outputVolume` is read-only, so a write
/// goes through the slider inside a hidden `MPVolumeView` — the workaround Apple
/// has left as the only one.
@MainActor
enum SystemVolume {
  /// The level right now, 0…1.
  static var level: Float { AVAudioSession.sharedInstance().outputVolume }

  /// Moves the system volume, which also moves what the hardware buttons see.
  static func set(_ level: Float) {
    guard let slider = slider() else { return }
    let value = min(max(level, 0), 1)
    // The slider applies the write on the next runloop turn, which also keeps it
    // from fighting the touch that is driving it.
    DispatchQueue.main.async { slider.value = value }
  }

  private static var host: MPVolumeView?

  private static func slider() -> UISlider? {
    if let slider = host?.subviews.compactMap({ $0 as? UISlider }).first { return slider }
    guard let window = keyWindow() else { return nil }

    // Off screen, tiny, and all but invisible: the view only has to exist for
    // its slider to be reachable.
    let view = MPVolumeView(frame: CGRect(x: -2_000, y: -2_000, width: 20, height: 20))
    view.alpha = 0.01
    window.addSubview(view)
    host = view
    return view.subviews.compactMap { $0 as? UISlider }.first
  }

  private static func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let window = scene.windows.first(where: { $0.isKeyWindow }) { return window }
    }
    return scenes.first?.windows.first
  }
}
