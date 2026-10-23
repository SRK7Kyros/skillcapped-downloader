import Foundation

/// What a picked folder turned out to be, worked out **away from the main
/// actor**: reading a folder that lives in another app's container can wait as
/// long as the file provider takes to answer, and a pick that did that on the
/// main thread froze the whole app — the iPad picker's "Open" spinner that never
/// stopped.
struct LibraryPick: Sendable, Equatable {
  var folder: URL
  var target: URL
  var ownFolder = false
  var insideDocuments = false
  var bookmark: Data?
  /// True when `target`'s security scope is held by this pick and must be given
  /// back by whoever ends up not using it.
  var scopeStarted = false
  var isCloud = false
  var visited = 0
  var capped = false
  var milliseconds = 0
  var problem: String?

  /// The folder the app will read, the folder it was handed, and how much work
  /// the look was — what the sheet's diagnostics print.
  var summary: String {
    var parts = [folder.lastPathComponent]
    if target.path != folder.path {
      parts.append("→ \(target.lastPathComponent)")
    }
    parts.append(visited == 1 ? "1 folder read" : "\(visited) folders read")
    parts.append("\(milliseconds) ms")
    if capped {
      parts.append("stopped early, the folder was too big to look through")
    }
    return parts.joined(separator: " · ")
  }

  var access: String {
    if ownFolder { return "The app's own folder — no permission needed." }
    return scopeStarted
      ? "Read through the folder's own security scope."
      : "No security scope was granted; only the sandbox's own access."
  }

  static func prepare(_ url: URL, documents: URL, manager: FileManager = .default) -> LibraryPick {
    let started = Date()
    let folder = url.standardizedFileURL
    let own = folder.path == documents.standardizedFileURL.path
    var pick = LibraryPick(folder: folder, target: own ? documents.standardizedFileURL : folder)
    pick.ownFolder = own

    let scoped = own ? false : folder.startAccessingSecurityScopedResource()

    if !own {
      let walk = LibraryLocator.walk(in: folder, depth: 2, manager: manager)
      pick.visited = walk.visited
      pick.capped = walk.capped
      if walk.libraries.count == 1 {
        pick.target = walk.libraries[0].standardizedFileURL
      }
    }

    pick.insideDocuments = isInside(pick.target, documents)
    let adopted = pick.target.path != folder.path
    if !own && !pick.insideDocuments {
      pick.bookmark = try? pick.target.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      if pick.bookmark == nil {
        pick.problem = "That folder could not be remembered. Copy it into the app instead: Files › On My iPhone › SkillCapped Local."
      }
    }
    pick.isCloud = ((try? pick.target.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem) ?? false

    if scoped {
      if adopted {
        pick.scopeStarted = pick.target.startAccessingSecurityScopedResource()
        folder.stopAccessingSecurityScopedResource()
      } else {
        pick.scopeStarted = true
      }
    }

    pick.milliseconds = Int(Date().timeIntervalSince(started) * 1000)
    return pick
  }

  private static func isInside(_ url: URL, _ root: URL) -> Bool {
    let path = url.standardizedFileURL.path
    let base = root.standardizedFileURL.path
    return path == base || path.hasPrefix(base + "/")
  }
}
