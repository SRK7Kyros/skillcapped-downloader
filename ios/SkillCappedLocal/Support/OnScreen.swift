import UIKit

/// The controller a sheet has to be raised from.
///
/// UIKit presents one controller per screen, so anything the app raises from
/// inside SwiftUI — the folder picker, the share sheet — has to hang off the
/// controller that is actually on top, never the one that owns the button: a
/// presentation made from a controller that is already covered is dropped
/// without a word, which reads as a button that does nothing.
enum OnScreen {
  /// The controller on screen, so a sheet rides above the page rather than under
  /// it.
  static func top() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    guard
      var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        ?? scene?.windows.first?.rootViewController
    else { return nil }

    while let presented = top.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }

  /// Presents `controller` from the top, answering whether there was anywhere to
  /// present it from. UIKit drops a presentation it cannot fulfil silently, so a
  /// caller that has to know checks `presentedViewController` in a completion.
  @discardableResult
  static func present(_ controller: UIViewController) -> Bool {
    guard let host = top() else { return false }
    host.present(controller, animated: true)
    return true
  }
}
