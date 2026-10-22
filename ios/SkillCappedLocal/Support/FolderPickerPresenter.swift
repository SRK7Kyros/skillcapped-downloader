import UIKit

/// Presents the system folder picker as a real modal.
///
/// The open-in-place folder browser is a Files browser, not an import sheet: iOS
/// gives it no Cancel of its own, so embedding it in a SwiftUI cover left the
/// user with no way out except picking something. Presented instead, it is a
/// sheet that can be swiped away and the cancellation reaches the delegate.
@MainActor
final class FolderPickerPresenter: NSObject, UIDocumentPickerDelegate {
  private static var live: FolderPickerPresenter?

  private let onPick: (URL?) -> Void

  private init(onPick: @escaping (URL?) -> Void) {
    self.onPick = onPick
  }

  static func present(_ picker: UIDocumentPickerViewController, onPick: @escaping (URL?) -> Void) {
    guard let host = topViewController() else { return }
    let presenter = FolderPickerPresenter(onPick: onPick)
    live = presenter
    picker.delegate = presenter
    picker.modalPresentationStyle = .pageSheet
    host.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(urls.first)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  private func finish(_ url: URL?) {
    let callback = onPick
    // The picker is still dismissing itself; release the delegate only after the
    // dismissal has unwound, or UIKit can call back into a freed delegate.
    DispatchQueue.main.async { Self.live = nil }
    callback(url)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
