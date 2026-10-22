import SwiftUI
import UIKit

/// The system folder picker, kept behind an Objective-C probe.
///
/// `UIDocumentPickerViewController` raises an Objective-C exception from its
/// initializer and Swift cannot catch one, so the build lives in
/// `Support/PickerProbe.m`: a build that cannot open the picker reports why
/// instead of dying, and the probe tries the open-in-place spellings a device
/// actually accepts before giving up.
enum FolderAccess {
  enum Outcome {
    case ready(UIDocumentPickerViewController)
    case unavailable(String)
  }

  static func picker(startingAt directory: URL?) -> Outcome {
    let result = SkillCappedFolderPickerResult.makeStarting(at: directory)
    guard let controller = result.controller as? UIDocumentPickerViewController else {
      return .unavailable(explanation(result.reason))
    }
    return .ready(controller)
  }

  /// UIKit's own reason first — the exact sentence is worth showing — then what
  /// the user can do about it in this build. Only blame the signing profile when
  /// UIKit named iCloud: the picker also refuses for reasons a profile cannot fix.
  static func explanation(_ reason: String?) -> String {
    let head = reason.flatMap { $0.isEmpty ? nil : $0 }
      ?? "This build cannot open the system folder picker."
    let why = head.lowercased().contains("icloud")
      ? "The picker needs the iCloud container entitlement, which only the signing profile can supply."
      : "The system refused to open the picker."
    return """
    \(head)

    \(why) Your library still works: copy the downloader's folder into On My \
    iPhone › SkillCapped Local and pick it from the list below.

    iOS \(UIDevice.current.systemVersion) · build \(Bundle.main.appVersion)
    """
  }
}

/// A ready picker plus the identity `sheet(item:)` needs.
struct FolderPickerRequest: Identifiable {
  let id = UUID()
  let controller: UIDocumentPickerViewController
}

/// Presents a picker built by `FolderAccess.picker()`.
struct FolderPickerSheet: UIViewControllerRepresentable {
  let controller: UIDocumentPickerViewController
  let onPick: (URL?) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onPick: onPick)
  }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL?) -> Void

    init(onPick: @escaping (URL?) -> Void) {
      self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      onPick(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      onPick(nil)
    }
  }
}
