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
    guard let host = OnScreen.top() else {
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
    // Dismissing the picker is the app's job, and until it happens UIKit keeps a
    // spinner exactly where **Open** was — which is what "it spins forever on
    // Open" was: the picker was never told to leave. Nothing may be done before
    // this, and nothing slow may follow it on the main thread.
    afterPickerGone { [weak self] in
      guard let self else { return }
      guard let picked = urls.first else {
        self.finish(.failure(.noFolder))
        return
      }
      // Whether the pick is a folder is a `stat`, and a `stat` on a URL from
      // another app's provider is an out-of-process round trip: off the main
      // thread, always.
      DispatchQueue.global(qos: .userInitiated).async {
        let folder = Self.isFolder(picked)
        DispatchQueue.main.async {
          self.finish(folder ? .success(picked) : .failure(.notAFolder))
        }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    afterPickerGone { [weak self] in self?.finish(.failure(.cancelled)) }
  }

  // MARK: - Plumbing

  /// Wait for the picker to actually leave the screen before answering, so the
  /// caller never dismisses the sheet underneath a controller that is still
  /// animating — UIKit drops that second dismissal and the picker stays up.
  ///
  /// `dismiss` does not call its completion when there is nothing to dismiss (a
  /// picker the system already took away), so that case is answered directly,
  /// and a dismissal that never reports back is answered after a moment.
  private func afterPickerGone(_ then: @escaping () -> Void) {
    guard let picker, picker.presentingViewController != nil else {
      self.picker = nil
      then()
      return
    }
    self.picker = nil
    var answered = false
    let once = {
      guard !answered else { return }
      answered = true
      then()
    }
    picker.dismiss(animated: true, completion: once)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: once)
  }

  private func finish(_ result: Result<URL, Failure>) {
    let callback = completion
    completion = nil
    callback?(result)
  }

  private static func isFolder(_ url: URL) -> Bool {
    if url.hasDirectoryPath { return true }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }
}
