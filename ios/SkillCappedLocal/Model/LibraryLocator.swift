import Foundation

/// Finds library folders the app can open without any system file picker.
///
/// A folder is a library when one of its immediate children is a bucket the
/// downloader writes (`Courses`, `Videos`, `Commentaries`). Sideloaded builds
/// cannot present `UIDocumentPickerViewController` at all — it requires the
/// iCloud Documents entitlement, a free Apple ID cannot grant it, and its
/// initializer throws `Application initializing document picker is missing the
/// iCloud entitlement` — so the app reads what iOS already exposes to it: its
/// own Documents folder, which Files shows as "On My iPhone › SkillCapped
/// Local".
enum LibraryLocator {
  /// Bucket folders the downloader writes under a library root.
  static let buckets = ["courses", "videos", "commentaries"]

  /// How deep to look below Documents for a library. The downloader's own layout
  /// is `Courses/<role>/<course>/`, so a copied library sits at depth 1–2.
  static let maxDepth = 4

  /// True when `url` holds a non-empty bucket folder. An empty `Courses` is not
  /// a library — it has nothing to read.
  static func isLibrary(_ url: URL, manager: FileManager = .default) -> Bool {
    directoryChildren(of: url, manager: manager).contains { child in
      buckets.contains(child.lastPathComponent.lowercased())
        && !directoryChildren(of: child, manager: manager).isEmpty
    }
  }

  /// Every library folder at or below `root`, shallowest first. A library is not
  /// searched further: its lessons are what it offers, and a nested copy would
  /// only duplicate them.
  static func libraries(in root: URL, manager: FileManager = .default) -> [URL] {
    var found: [URL] = []
    var queue: [(url: URL, depth: Int)] = [(root, 0)]
    while !queue.isEmpty {
      let (url, depth) = queue.removeFirst()
      if isLibrary(url, manager: manager) {
        found.append(url)
        continue
      }
      guard depth < maxDepth else { continue }
      queue.append(contentsOf: directoryChildren(of: url, manager: manager).map { ($0, depth + 1) })
    }
    return found
  }

  private static func directoryChildren(of url: URL, manager: FileManager) -> [URL] {
    let children = (try? manager.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    return children
      .filter { isDirectory($0, manager: manager) }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  private static func isDirectory(_ url: URL, manager: FileManager) -> Bool {
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
    return isDirectory.boolValue
  }
}
