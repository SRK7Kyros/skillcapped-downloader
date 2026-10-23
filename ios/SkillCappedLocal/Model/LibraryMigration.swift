import Foundation

/// Moving the library's content to the folder the user just picked.
///
/// Until a folder is chosen the app downloads into its own Documents folder, so a
/// pick is never only "look somewhere else": whatever is already on the phone
/// belongs where the browser now looks. The downloader's layout is preserved, a
/// library that is already there is merged into, and nothing is deleted that is
/// not provably a second copy — the same relative path holding the same number of
/// bytes. A file the destination answers with something else is left where it is
/// and named in the report, because a move must never overwrite a library.
enum LibraryMigration {
  /// The downloader's own layout, plus the catalogue cache the desktop build
  /// writes beside the files it names.
  static let carried: Set<String> = ["courses", "videos", "commentaries", ".skillcapped"]
  /// A loose lesson sitting at the top of the library, which the scanner lists as
  /// a video. Anything else at the top of a library is not the app's to move.
  static let looseFiles: Set<String> = DownloadName.playableExtensions

  struct Progress: Equatable, Sendable {
    var done = 0
    var total = 0
    var bytes: Int64 = 0
    /// True until the move itself has begun, i.e. while a lesson already being
    /// written is allowed to finish first.
    var waiting = false

    var label: String {
      if waiting { return "Waiting for the current download…" }
      guard total > 0 else { return "Moving your downloads…" }
      return "Moving \(done) of \(total)…"
    }
  }

  struct Report: Equatable, Sendable {
    var moved = 0
    /// Second copies of a file that was already there, which the old folder no
    /// longer needs.
    var merged = 0
    var bytes: Int64 = 0
    /// Files left in the old folder because a different file already sits at
    /// their name.
    var kept: [String] = []
    var failed: [String] = []

    var isEmpty: Bool { moved == 0 && merged == 0 && kept.isEmpty && failed.isEmpty }

    var note: String {
      guard !isEmpty else { return "" }
      var parts: [String] = []
      if moved > 0 {
        parts.append("Moved \(Format.count(moved, "file", "files")) (\(Format.bytes(bytes)))")
      }
      if merged > 0 { parts.append("\(merged) were already there") }
      if !failed.isEmpty { parts.append("\(Format.count(failed.count, "file", "files")) could not be moved") }
      if !kept.isEmpty { parts.append("\(kept.count) left in the old folder") }
      return parts.joined(separator: " · ") + "."
    }
  }

  struct Move: Equatable, Sendable {
    let source: URL
    let destination: URL
    let bytes: Int64
  }

  /// A move is only meaningful between two folders that are neither the same nor
  /// one inside the other — moving a folder into itself, or into its own child,
  /// would walk its own tail.
  static func canMove(from source: URL, to destination: URL) -> Bool {
    let from = source.standardizedFileURL.path
    let to = destination.standardizedFileURL.path
    guard from != to else { return false }
    return !isInside(from, to) && !isInside(to, from)
  }

  /// Every file the move would carry, with the place it takes in `destination`.
  static func plan(from source: URL, to destination: URL) -> [Move] {
    let manager = FileManager.default
    let root = source.standardizedFileURL
    let depth = root.pathComponents.count
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    guard let walk = manager.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: nil) else {
      return []
    }

    var moves: [Move] = []
    while let url = walk.nextObject() as? URL {
      let components = url.standardizedFileURL.pathComponents
      guard components.count > depth else { continue }
      let relative = Array(components[depth...])
      guard let top = relative.first else { continue }
      let bucket = top.lowercased()
      let loose = relative.count == 1 && looseFiles.contains(url.pathExtension.lowercased())
      guard carried.contains(bucket) || loose else { continue }
      // A lesson that is still in iCloud is a hidden shadow file; its bytes are
      // not here to move, and fetching a whole library to relocate it is not a
      // move. It stays where it is, reachable at its own library.
      guard !relative.dropFirst().contains(where: { $0.hasPrefix(".") }) else { continue }
      let values = try? url.resourceValues(forKeys: Set(keys))
      guard values?.isRegularFile == true else { continue }

      moves.append(Move(
        source: url,
        destination: destination.appendingPathComponent(relative.joined(separator: "/"), isDirectory: false),
        bytes: Int64(values?.fileSize ?? 0)
      ))
    }
    return moves
  }

  /// Carry the library over. Synchronous and file-bound, so a caller runs it off
  /// the main actor when the two folders sit on different volumes and the move is
  /// really a copy. `onProgress` is called as the work lands, never for every
  /// file of a large library.
  static func run(
    from source: URL,
    to destination: URL,
    onProgress: @Sendable (Progress) -> Void = { _ in }
  ) -> Report {
    let manager = FileManager.default
    var report = Report()
    let moves = plan(from: source, to: destination)
    let total = moves.count
    var progress = Progress(done: 0, total: total)
    if total > 0 { onProgress(progress) }

    for (index, move) in moves.enumerated() {
      let there = existing(move.destination)
      if there.exists {
        // The same file, under the same name, is already in the destination:
        // the copy in the old folder is a second copy.
        if let size = there.size, size == move.bytes, (try? manager.removeItem(at: move.source)) != nil {
          report.merged += 1
        } else {
          report.kept.append(relative(move.source, in: source))
        }
      } else {
        do {
          try manager.createDirectory(at: move.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
          try manager.moveItem(at: move.source, to: move.destination)
          report.moved += 1
          report.bytes += move.bytes
        } catch {
          report.failed.append(relative(move.source, in: source))
        }
      }

      progress.done = index + 1
      progress.total = total
      progress.bytes = report.bytes
      if progress.done % 25 == 0 || progress.done == total { onProgress(progress) }
    }

    pruneEmptyFolders(in: source)
    return report
  }

  /// Where a path the downloader remembers lands once the library has moved, or
  /// nil when the file was never under the old folder.
  static func relocated(_ path: String, from source: URL, to destination: URL) -> String? {
    let root = source.standardizedFileURL.path
    guard path.hasPrefix(root + "/") else { return nil }
    let rest = String(path.dropFirst(root.count + 1))
    return destination.appendingPathComponent(rest, isDirectory: false).path
  }

  // MARK: - Files

  private static func existing(_ url: URL) -> (exists: Bool, size: Int64?) {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return (false, nil)
    }
    guard !isDirectory.boolValue else { return (true, nil) }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    return (true, size.map(Int64.init))
  }

  /// Folders the move emptied — `Courses/<role>/<course>` whose lessons all left
  /// — are dropped, so the old library does not linger as a maze of empty boxes.
  /// Nothing outside what the app carries is pruned.
  private static func pruneEmptyFolders(in root: URL) {
    let manager = FileManager.default
    let depth = root.standardizedFileURL.pathComponents.count
    guard let walk = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil) else {
      return
    }
    var folders: [URL] = []
    while let url = walk.nextObject() as? URL {
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
      let components = url.standardizedFileURL.pathComponents
      guard components.count > depth, let top = components.dropFirst(depth).first else { continue }
      guard carried.contains(top.lowercased()) else { continue }
      folders.append(url)
    }
    for folder in folders.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
      guard let contents = try? manager.contentsOfDirectory(atPath: folder.path), contents.isEmpty else { continue }
      try? manager.removeItem(at: folder)
    }
  }

  private static func relative(_ url: URL, in root: URL) -> String {
    let base = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(base + "/") else { return path }
    return String(path.dropFirst(base.count + 1))
  }

  private static func isInside(_ path: String, _ root: String) -> Bool {
    path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }
}
