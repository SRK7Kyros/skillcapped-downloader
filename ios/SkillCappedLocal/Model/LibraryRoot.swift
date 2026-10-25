import Foundation

/// Where the queue writes when there is no scene to ask.
///
/// A relaunch in the background has no `LibraryStore`, so the folder the library
/// lives in is answered from what the store saved when it was chosen. At most one
/// of the two entries is set at a time: a Documents-relative path for a folder
/// inside the app's own container, or a security-scoped bookmark for one picked
/// anywhere else.
struct LibraryRoot {
  /// Written by `LibraryStore`; both sides read the same keys, so the folder a
  /// download lands in can never depend on which of them answered.
  static let bookmarkKey = "library.bookmark"
  static let pathKey = "library.relativePath"

  let url: URL
  /// True when this answer started the folder's security scope, which the caller
  /// therefore holds for as long as it writes there.
  let scoped: Bool

  /// The folder the app reads and writes, or nil when a folder was saved but
  /// cannot be reached right now.
  ///
  /// Nil is deliberately not "the app's own folder": a lesson must never land in
  /// the sandbox because a bookmark went stale while the library sits somewhere
  /// else. The store repairs the choice the next time the app is opened, and the
  /// queue picks up again then.
  static func resolve(defaults: UserDefaults = .standard, documents: URL) -> LibraryRoot? {
    if let relative = defaults.string(forKey: pathKey) {
      // An empty path is how the store records the app's own folder.
      guard !relative.isEmpty else { return LibraryRoot(url: documents, scoped: false) }
      let url = documents.appendingPathComponent(relative, isDirectory: true)
      guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
      return LibraryRoot(url: url, scoped: false)
    }

    guard let data = defaults.data(forKey: bookmarkKey) else {
      // Nothing was ever chosen, and the app's own folder is always a library.
      return LibraryRoot(url: documents, scoped: false)
    }

    var stale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    ) else { return nil }

    // The scope is started before the folder is asked about: from outside the
    // sandbox, an unscoped read answers no even though the bookmark is good.
    let scoped = url.startAccessingSecurityScopedResource()
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      if scoped { url.stopAccessingSecurityScopedResource() }
      return nil
    }
    return LibraryRoot(url: url, scoped: scoped)
  }

  /// Give back the scope a resolution started, when the folder is no longer used.
  func stop() {
    guard scoped else { return }
    url.stopAccessingSecurityScopedResource()
  }
}
