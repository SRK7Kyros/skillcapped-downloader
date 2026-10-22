import UIKit

/// Puts the picker `FolderAccess` built on screen.
///
/// The picker is presented for real: never embedded as a child of another
/// controller (that renders it with no chrome of its own), and never rebuilt by
/// SwiftUI — `.fileImporter` constructs the picker again where a raise cannot be
/// caught. The style stays at UIKit's default so a sheet can always be swiped
/// away, even if a system build renders it empty.
final class FolderPickerPresenter: NSObject, UIDocumentPickerDelegate {
  enum Failure: LocalizedError {
    case nothingToPresent
    case didNotAppear
    case notAFolder
    case noFolder
    case cancelled

    var errorDescription: String? {
      switch self {
      case .nothingToPresent:
        return "There was no screen to open the picker from."
      case .didNotAppear:
        return "The system picker did not appear. Its diagnostics are in the section below."
      case .notAFolder:
        return "That was a file, not a folder. Pick the folder itself — a folder shows a folder icon."
      case .noFolder:
        return "The picker returned nothing. Try again, or copy the folder in."
      case .cancelled:
        return nil
      }
    }
  }

  private var picker: UIViewController?
  private var completion: ((Result<URL, Failure>) -> Void)?

  func present(
    _ picker: UIViewController,
    completion: @escaping (Result<URL, Failure>) -> Void
  ) {
    guard let host = Self.top() else {
      completion(.failure(.nothingToPresent))
      return
    }

    self.picker = picker
    self.completion = completion
    (picker as? UIDocumentPickerViewController)?.delegate = self

    host.present(picker, animated: true) { [weak self] in
      // UIKit silently drops a presentation it cannot fulfil; say so instead of
      // leaving the button looking like it did nothing.
      if host.presentedViewController !== picker {
        self?.finish(.failure(.didNotAppear))
      }
    }
  }

  // MARK: - UIDocumentPickerDelegate

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    if let folder = urls.first(where: isFolder) {
      finish(.success(folder))
      return
    }
    finish(.failure(urls.isEmpty ? .noFolder : .notAFolder))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(.failure(.cancelled))
  }

  // MARK: - Plumbing

  private func finish(_ result: Result<URL, Failure>) {
    let callback = completion
    completion = nil
    picker = nil
    callback?(result)
  }

  private func isFolder(_ url: URL) -> Bool {
    if url.hasDirectoryPath { return true }
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
    return values?.isDirectory == true
  }

  /// The controller actually on screen, so the picker rides above the sheet
  /// rather than under it.
  private static func top() -> UIViewController? {
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
}
