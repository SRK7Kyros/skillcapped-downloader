import Foundation

/// Finds library folders, i.e. folders holding the buckets the downloader writes.
///
/// A folder is a library when one of its immediate children is `Courses`,
/// `Videos` or `Commentaries` and that bucket is not empty. Nothing here needs
/// the files themselves — a listing is metadata — so the same walk works on a
/// folder in iCloud Drive that this device has not downloaded.
enum LibraryLocator {
  /// Bucket folders the downloader writes under a library root.
  static let buckets = ["courses", "videos", "commentaries"]

  /// How deep to look below a root for a library. The downloader's own layout is
  /// `Courses/<role>/<course>/`, so a library sits at depth 1–2.
  static let maxDepth = 4

  /// True when `url` holds a non-empty bucket folder. An empty `Courses` is not
  /// a library — it has nothing to read.
  static func isLibrary(_ url: URL, manager: FileManager = .default) -> Bool {
    directoryChildren(of: url, manager: manager).contains { child in
      buckets.contains(child.lastPathComponent.lowercased()) && hasVisibleEntries(child, manager: manager)
    }
  }

  /// Every library folder at or below `root`, shallowest first. A library is not
  /// searched further: its lessons are what it offers, and a nested copy would
  /// only duplicate them. `depth` caps the walk, which a folder handed back by
  /// the picker uses to look only one level down.
  static func libraries(in root: URL, depth limit: Int = maxDepth, manager: FileManager = .default) -> [URL] {
    var found: [URL] = []
    var queue: [(url: URL, depth: Int)] = [(root, 0)]
    while !queue.isEmpty {
      let (url, depth) = queue.removeFirst()
      if isLibrary(url, manager: manager) {
        found.append(url)
        continue
      }
      guard depth < limit else { continue }
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

  private static func hasVisibleEntries(_ url: URL, manager: FileManager) -> Bool {
    let entries = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return !entries.isEmpty
  }

  private static func isDirectory(_ url: URL, manager: FileManager) -> Bool {
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
    return isDirectory.boolValue
  }
}
