import UIKit

/// The system folder picker, kept behind an Objective-C probe.
///
/// `UIDocumentPickerViewController` raises an Objective-C exception from its
/// initializer and Swift cannot catch one, so the build lives in
/// `Support/PickerProbe.m`: a build that cannot open the picker reports why
/// instead of dying, and the probe walks the spellings a device actually accepts
/// before giving up.
enum FolderAccess {
  enum Outcome {
    case ready(UIDocumentPickerViewController)
    case unavailable(String)
  }

  /// One spelling the probe tried, for the in-app diagnostics.
  struct Attempt: Identifiable {
    let name: String
    let ok: Bool
    let detail: String?

    var id: String { name }
  }

  static func picker(startingAt directory: URL?) -> Outcome {
    let result = SkillCappedFolderPickerResult.makeStarting(at: directory)
    guard let controller = result.controller as? UIDocumentPickerViewController else {
      return .unavailable(explanation(result.reason))
    }
    return .ready(controller)
  }

  /// Which spells this build's iOS accepts, in the order the probe tries them.
  ///
  /// The first accepted one is what the folder button uses, so a device that
  /// refuses the folder-only picker can say so in the sheet instead of refusing
  /// silently — and a spelling that starts working again is adopted on its own.
  static func survey() -> [Attempt] {
    SkillCappedFolderPickerResult.survey().compactMap { row in
      guard let name = row["name"] as? String else { return nil }
      return Attempt(
        name: name,
        ok: (row["ok"] as? Bool) ?? false,
        detail: row["detail"] as? String
      )
    }
  }

  /// Whether this build can open the picker at all.
  static func refusal(startingAt directory: URL?) -> String? {
    switch picker(startingAt: directory) {
    case .ready:
      return nil
    case let .unavailable(reason):
      return reason
    }
  }

  /// UIKit's own reason first — the exact sentence is worth showing — then what
  /// the user can do about it in this build. Only blame the signing profile when
  /// UIKit named iCloud: the picker also refuses for reasons a profile cannot fix.
  static func explanation(_ reason: String?) -> String {
    let head = reason.flatMap { $0.isEmpty ? nil : $0 }
      ?? "This build cannot open the system folder picker."
    let why = head.lowercased().contains("icloud")
      ? "The picker wants an iCloud container only the signing profile can grant."
      : "This iOS refused every folder-picker spelling the build knows."
    return """
    \(head)

    \(why) Your library still works: copy the downloader's folder into On My \
    iPhone › SkillCapped Local and pick it from the list below.

    iOS \(UIDevice.current.systemVersion) · build \(Bundle.main.appVersion)
    """
  }
}
