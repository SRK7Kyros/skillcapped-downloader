import UIKit

/// How Files names the folders this app works with.
///
/// The app's own folder is `On My iPhone › SkillCapped Local` (or `On My iPad`),
/// and that is what the screens must say — a sandbox path such as
/// `/var/mobile/Containers/Data/Application/<uuid>/Documents` reads as hidden
/// storage to anyone who is not an Xcode user, even though it is the very folder
/// Files shows.
enum FilesPlace {
  static var device: String {
    UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone"
  }

  /// "On My iPhone › SkillCapped Local"
  static var ownFolder: String { "\(device) › SkillCapped Local" }

  /// Where a folder outside the app shows up, as far as the app can tell: an
  /// iCloud Drive folder keeps its own name under iCloud Drive, and anything else
  /// is on the device.
  static func describe(_ url: URL, isCloud: Bool) -> String {
    let name = url.lastPathComponent
    guard !name.isEmpty else { return isCloud ? "iCloud Drive" : device }
    return isCloud ? "iCloud Drive › \(name)" : "\(device) › \(name)"
  }
}
