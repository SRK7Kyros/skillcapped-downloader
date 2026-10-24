import AVKit
import SwiftUI
import UIKit

/// The system's own output menu, drawn in the player's header: AirPlay screens
/// and speakers, Bluetooth headphones, and back to the phone's speaker, switched
/// from where every other phone player offers it.
///
/// `AVRoutePickerView` is the only public way to that list — building one would
/// not reach AirPlay's own authentication — and it takes the app's AirPlay
/// because the player already allows external playback.
@MainActor
struct RoutePicker: UIViewRepresentable {
  var diameter: CGFloat = 30

  func makeUIView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.tintColor = .white
    view.activeTintColor = UIColor(Palette.brand)
    view.prioritizesVideoDevices = true
    view.backgroundColor = UIColor.black.withAlphaComponent(0.42)
    view.layer.cornerRadius = diameter / 2
    view.clipsToBounds = true
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentCompressionResistancePriority(.required, for: .horizontal)
    return view
  }

  func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
