import Foundation

@MainActor
final class LibraryStore: ObservableObject {
  @Published private(set) var scan: LibraryScan?
  @Published private(set) var scanning = false
  @Published private(set) var message: String?
  @Published private(set) var rootName: String?
  /// True when the library sits in iCloud Drive, where a lesson may still be a
  /// placeholder until playback asks for it.
  @Published private(set) var isCloudRoot = false
  /// Library folders the app can already read, i.e. what it found in Documents.
  @Published private(set) var candidates: [URL] = []

  private static let bookmarkKey = "library.bookmark"
  private static let pathKey = "library.relativePath"
  private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  private var scoped: URL?

  var hasFolder: Bool { scoped != nil }
  /// "On My iPhone › SkillCapped Local" — the one folder the app may read without
  /// the iCloud entitlement a sideloaded build cannot have.
  var documentsURL: URL { documents }

  init() {
    if let demo = DemoLibrary.root() {
      attach(demo, persist: false)
      return
    }
    restore()
  }

  deinit {
    scoped?.stopAccessingSecurityScopedResource()
  }

  /// Reopen the last library, or adopt the only one waiting in Documents.
  func restore() {
    if attachSavedPath() { return }
    if attachBookmark() { return }
    refreshCandidates()
    if candidates.count == 1, let only = candidates.first {
      choose(only)
    } else if candidates.count > 1 {
      message = "\(candidates.count) library folders are waiting — choose one."
    }
  }

  func refreshCandidates() {
    candidates = LibraryLocator.libraries(in: documents)
  }

  /// Point the library at `url` — a folder the system picker handed back, one of
  /// the folders waiting in Documents, or a folder another app opened. A folder
  /// inside the app's own Documents needs no bookmark (the sandbox already grants
  /// it) while anything from outside is remembered as a security-scoped bookmark,
  /// which is also what keeps an iCloud Drive folder reachable across launches.
  func choose(_ url: URL) {
    let target = library(in: url).standardizedFileURL
    if isInsideDocuments(target) {
      UserDefaults.standard.set(relativePath(of: target), forKey: Self.pathKey)
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
      attach(target, persist: false)
      return
    }
    guard let bookmark = try? target.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
      message = "That folder could not be remembered. Copy it into the app instead: Files › On My iPhone › SkillCapped Local."
      return
    }
    UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
    UserDefaults.standard.removeObject(forKey: Self.pathKey)
    attach(target, persist: false)
  }

  /// A pick may be the library itself or the folder that holds it — iCloud
  /// Drive's root, a Downloads folder. Adopt the only library one level down,
  /// and otherwise take the folder as given (scanning reports what it found).
  private func library(in url: URL) -> URL {
    guard !LibraryLocator.isLibrary(url) else { return url }
    let found = LibraryLocator.libraries(in: url, depth: 2)
    return found.count == 1 ? found[0] : url
  }

  func isCurrent(_ url: URL) -> Bool {
    guard let scoped else { return false }
    return scoped.standardizedFileURL.path == url.standardizedFileURL.path
  }

  func forget() {
    UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    UserDefaults.standard.removeObject(forKey: Self.pathKey)
    scoped?.stopAccessingSecurityScopedResource()
    scoped = nil
    scan = nil
    rootName = nil
    isCloudRoot = false
    message = nil
    Task { await PosterStore.shared.forget() }
  }

  func rescan() {
    guard let root = scoped else { return }
    scanning = true
    message = nil
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        let catalog = CatalogIndex.load(root: root) ?? .empty
        return LibraryScanner.scan(root: root, catalog: catalog)
      }.value
      scan = result
      scanning = false
      if result.isEmpty {
        message = "No lessons found. Point the app at the folder that holds Courses, Videos and Commentaries."
      }
    }
  }

  private func attachSavedPath() -> Bool {
    guard let relative = UserDefaults.standard.string(forKey: Self.pathKey) else { return false }
    let url = relative.isEmpty ? documents : documents.appendingPathComponent(relative, isDirectory: true)
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      UserDefaults.standard.removeObject(forKey: Self.pathKey)
      return false
    }
    attach(url, persist: false)
    return true
  }

  private func attachBookmark() -> Bool {
    guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return false }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
      return false
    }
    attach(url, persist: stale)
    return true
  }

  private func attach(_ url: URL, persist: Bool) {
    let started = url.startAccessingSecurityScopedResource()
    scoped = url
    rootName = displayName(for: url)
    isCloudRoot = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    if persist, let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
    }
    if !started, !FileManager.default.isReadableFile(atPath: url.path) {
      message = "This folder is no longer available. Add it again through the library sheet."
    }
    rescan()
  }

  /// Files shows the app's own Documents folder under the app's name, so that is
  /// what the sheet calls it; anything else keeps its own name.
  private func displayName(for url: URL) -> String {
    isSamePath(url, documents) ? "SkillCapped Local" : url.lastPathComponent
  }

  private func isInsideDocuments(_ url: URL) -> Bool {
    let root = documents.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    return path == root || path.hasPrefix(root + "/")
  }

  private func relativePath(of url: URL) -> String {
    let root = documents.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(root + "/") else { return "" }
    return String(path.dropFirst(root.count + 1))
  }

  private func isSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
  }
}
