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

  /// How many folders one walk will look at before it stops. Every folder it
  /// looks at is at least two directory listings — on a folder that lives in
  /// another app's container (iCloud Drive, a file provider) each of those is a
  /// round trip outside this process — so an unbounded walk over a tree nobody
  /// expected can take minutes. A pick that took minutes looked like a frozen
  /// app; a walk that stops early still answers, and says that it did.
  static let walkBudget = 400

  /// What a walk saw, so a caller can say how much work it was.
  struct Walk: Sendable, Equatable {
    var libraries: [URL] = []
    var visited = 0
    /// True when the budget ran out before the tree did.
    var capped = false
  }

  /// Every library folder at or below `root`, shallowest first. A library is not
  /// searched further: its lessons are what it offers, and a nested copy would
  /// only duplicate them. `depth` is the deepest level whose folders are still
  /// tested (the root is 0); a folder handed back by the picker passes 2, so the
  /// walk looks a couple of levels in without crawling an iCloud Drive root.
  static func libraries(in root: URL, depth limit: Int = maxDepth, manager: FileManager = .default) -> [URL] {
    walk(in: root, depth: limit, manager: manager).libraries
  }

  /// The walk itself, with the count and whether it had to stop early. Callers
  /// that show the user what happened use this; the rest use `libraries(in:)`.
  static func walk(
    in root: URL,
    depth limit: Int = maxDepth,
    budget: Int = walkBudget,
    manager: FileManager = .default
  ) -> Walk {
    var seen = Walk()
    var queue: [(url: URL, depth: Int)] = [(root, 0)]
    while !queue.isEmpty {
      guard seen.visited < budget else {
        seen.capped = true
        break
      }
      let (url, depth) = queue.removeFirst()
      seen.visited += 1
      if isLibrary(url, manager: manager) {
        seen.libraries.append(url)
        continue
      }
      guard depth < limit else { continue }
      queue.append(contentsOf: directoryChildren(of: url, manager: manager).map { ($0, depth + 1) })
    }
    return seen
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
