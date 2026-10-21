import Foundation

@MainActor
final class LibraryStore: ObservableObject {
  @Published private(set) var scan: LibraryScan?
  @Published private(set) var scanning = false
  @Published private(set) var message: String?
  @Published private(set) var rootName: String?

  private static let bookmarkKey = "library.bookmark"
  private var scoped: URL?

  var hasFolder: Bool { scoped != nil }

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

  func restore() {
    guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
      return
    }
    attach(url, persist: stale)
  }

  func choose(_ url: URL) {
    guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
      message = "That folder could not be remembered. Pick it again after relaunching."
      return
    }
    UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
    attach(url, persist: false)
  }

  func forget() {
    UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    scoped?.stopAccessingSecurityScopedResource()
    scoped = nil
    scan = nil
    rootName = nil
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

  private func attach(_ url: URL, persist: Bool) {
    let started = url.startAccessingSecurityScopedResource()
    scoped = url
    rootName = url.lastPathComponent
    if persist, let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
    }
    if !started, !FileManager.default.isReadableFile(atPath: url.path) {
      message = "This folder is no longer available. Pick it again to restore access."
    }
    rescan()
  }
}
