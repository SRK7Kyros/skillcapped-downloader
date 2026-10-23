import Foundation

/// The app's own folder, ready to receive lessons before anything is downloaded.
///
/// `Files › On My iPhone › SkillCapped Local` is the app's Documents folder — the
/// one place it may always read and write, and the one the user can see. The
/// buckets are created there on the first launch so it is obvious where a lesson
/// lands, and so the app has a library even when nothing has been picked.
enum LibraryBootstrap {
  /// Bucket folders, spelled as Files shows them. They are the same buckets
  /// `LibraryLocator` looks for, only capitalised for display.
  static let buckets = ["Courses", "Videos", "Commentaries"]

  /// Creates the buckets and answers where they are. Idempotent: an existing
  /// folder (with lessons in it) is left exactly as it is.
  @discardableResult
  static func createBuckets(in root: URL, manager: FileManager = .default) -> [URL] {
    buckets.map { name in
      let url = root.appendingPathComponent(name, isDirectory: true)
      try? manager.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }
  }
}
