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
  @Published private(set) var rootURL: URL?
  /// Set while the old library's content is carried into the new one.
  @Published private(set) var moving: LibraryMigration.Progress?
  /// The folder a pick is reading right now, named so the banner can say what it
  /// is waiting for instead of spinning anonymously.
  @Published private(set) var preparing: String?
  /// What the last pick found and how long it took.
  @Published private(set) var lastPick: LibraryPick?
  private var preparingToken: UUID?
  /// The catalogue the app has fetched. A folder this phone filled itself has no
  /// `.skillcapped/catalog.json` — only one that came from the desktop carries it
  /// — so without this the lessons would have no titles, no order, no durations
  /// and no posters.
  private var catalogue = CatalogIndex.empty

  private static let bookmarkKey = "library.bookmark"
  private static let pathKey = "library.relativePath"
  private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  private var scoped: URL?

  /// Holds the download queue and lets the lesson being written finish, so
  /// nothing is carried off half-written.
  var beforeMove: (@MainActor () async -> Void)?
  /// Lets remembered absolute paths follow their files, and restarts the queue.
  var afterMove: (@MainActor (URL, URL) -> Void)?

  /// True when the library is a folder the user picked somewhere else. The app's
  /// own folder is not "chosen", it is simply where the app lives.
  var hasFolder: Bool { scoped != nil }

  /// "On My iPhone › SkillCapped Local" — the one folder the app may always read,
  /// whatever the system picker allows, and the default library.
  var documentsURL: URL { documents }

  /// What the app reads and writes: the folder the user picked, or the app's own
  /// folder in Files. Never nil — the app is always pointed at a library.
  var libraryURL: URL { scoped ?? documents }

  var usingOwnFolder: Bool {
    guard let scoped else { return true }
    return isSamePath(scoped, documents)
  }

  /// Where Files shows the library, in the words Files uses — never a sandbox
  /// path, which reads as hidden storage to anyone who is not an Xcode user.
  var filesLocation: String {
    guard let scoped, !usingOwnFolder else { return FilesPlace.ownFolder }
    if isInsideDocuments(scoped) {
      let tail = relativePath(of: scoped)
      return tail.isEmpty ? FilesPlace.ownFolder : "\(FilesPlace.ownFolder) › \(tail)"
    }
    return FilesPlace.describe(scoped, isCloud: isCloudRoot)
  }

  /// Where a download is written: the library the app is pointed at, so a
  /// finished lesson lands beside the ones already there.
  var downloadRoot: URL { libraryURL }

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

  /// Reopen the last library, or adopt the only one waiting in Documents — and
  /// otherwise settle on the app's own folder, which always exists.
  func restore() {
    if attachSavedPath() { return }
    if attachBookmark() { return }
    refreshCandidates()
    if candidates.count == 1, let only = candidates.first {
      choose(only)
      return
    }
    adoptOwnFolder()
    // After the adopt, because scanning clears the message it starts with.
    if candidates.count > 1 {
      message = "\(candidates.count) library folders are waiting — choose one."
    }
  }

  /// The app's own folder is a library from the first launch: Files shows the
  /// three buckets, and a lesson downloaded here lands in them.
  func adoptOwnFolder() {
    LibraryBootstrap.createBuckets(in: documents)
    scoped = nil
    rootURL = documents
    rootName = displayName(for: documents)
    isCloudRoot = false
    scan = nil
    rescan()
  }

  func refreshCandidates() {
    candidates = LibraryLocator.libraries(in: documents)
  }

  /// Point the store at the catalogue the app has fetched, and read the folder
  /// again so its lessons gain their titles, order, durations and posters.
  func adopt(catalog: CatalogIndex) {
    guard !catalog.isEmpty else { return }
    guard catalog.generatedAt != catalogue.generatedAt
      || catalog.byId.count != catalogue.byId.count else { return }
    catalogue = catalog
    rescan()
  }

  /// Point the library at `url` — a folder the system picker handed back, one of
  /// the folders waiting in Documents, or a folder another app opened. A folder
  /// inside the app's own Documents needs no bookmark (the sandbox already grants
  /// it) while anything from outside is remembered as a security-scoped bookmark,
  /// which is also what keeps an iCloud Drive folder reachable across launches.
  /// Whatever was downloaded into the previous folder is moved to this one.
  ///
  /// The reading happens off the main actor (`LibraryPick.prepare`): a folder in
  /// another app's container answers through its file provider, and doing that
  /// here used to freeze the app the moment the picker's **Open** was tapped.
  @discardableResult
  func choose(_ url: URL) -> Bool {
    guard moving == nil, preparing == nil else {
      message = "Still opening the last folder — try again in a moment."
      return false
    }
    let previous = downloadRoot.standardizedFileURL
    let previousScoped = scoped

    // The app's own folder is taken as itself, never through a library that
    // happens to sit inside it — and it needs no reading, so it stays immediate.
    if isSamePath(url, documents) {
      apply(LibraryPick.prepare(url, documents: documents), previous: previous, previousScoped: previousScoped)
      return true
    }

    let documents = self.documents
    let token = UUID()
    preparingToken = token
    preparing = displayName(for: url)
    Task { [weak self] in
      let pick = await Task.detached(priority: .userInitiated) {
        LibraryPick.prepare(url, documents: documents)
      }.value
      guard let self else {
        if pick.scopeStarted { pick.target.stopAccessingSecurityScopedResource() }
        return
      }
      guard preparingToken == token else {
        // Stopped by the user, or a newer pick won: give the scope back.
        if pick.scopeStarted { pick.target.stopAccessingSecurityScopedResource() }
        return
      }
      preparingToken = nil
      preparing = nil
      lastPick = pick
      apply(pick, previous: previous, previousScoped: previousScoped)
    }
    return true
  }

  /// Give up on a folder that is taking too long to read. Nothing moves: the
  /// library stays where it was, which is the point — a pick can never wedge the
  /// app, however long the file provider takes.
  func stopPreparing() {
    guard preparing != nil else { return }
    preparingToken = nil
    preparing = nil
    message = "Left the library where it was."
  }

  private func apply(_ pick: LibraryPick, previous: URL, previousScoped: URL?) {
    if pick.ownFolder {
      UserDefaults.standard.set("", forKey: Self.pathKey)
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
      adoptOwnFolder()
      moveLibrary(from: previous, to: pick.target, releasing: previousScoped)
      return
    }
    if pick.insideDocuments {
      UserDefaults.standard.set(relativePath(of: pick.target), forKey: Self.pathKey)
      UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    } else {
      guard let bookmark = pick.bookmark else {
        if pick.scopeStarted { pick.target.stopAccessingSecurityScopedResource() }
        message = pick.problem
          ?? "That folder could not be remembered. Copy it into the app instead: Files › On My iPhone › SkillCapped Local."
        return
      }
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
      UserDefaults.standard.removeObject(forKey: Self.pathKey)
    }
    attach(
      pick.target,
      persist: false,
      scopeStarted: pick.scopeStarted,
      isCloud: pick.isCloud
    )
    moveLibrary(from: previous, to: pick.target, releasing: previousScoped)
  }

  func isCurrent(_ url: URL) -> Bool {
    isSamePath(libraryURL, url)
  }

  /// Carry the previous folder's content into the new one, off the main actor:
  /// between two volumes the move is a copy, and a library is gigabytes.
  private func moveLibrary(from source: URL, to destination: URL, releasing previous: URL?) {
    let release = previous.flatMap { url in
      url.standardizedFileURL.path == scoped?.standardizedFileURL.path ? nil : url
    }
    guard LibraryMigration.canMove(from: source, to: destination),
          FileManager.default.fileExists(atPath: source.path)
    else {
      release?.stopAccessingSecurityScopedResource()
      return
    }

    moving = LibraryMigration.Progress(waiting: true)
    Task { [weak self] in
      guard let self else { return }
      await beforeMove?()
      let report = await Task.detached(priority: .utility) {
        LibraryMigration.run(from: source, to: destination) { progress in
          Task { @MainActor [weak self] in
            guard self?.moving != nil else { return }
            self?.moving = progress
          }
        }
      }.value
      afterMove?(source, destination)
      release?.stopAccessingSecurityScopedResource()
      moving = nil
      // `rescan` clears the message as it starts, so the report is said after it.
      rescan()
      message = report.note.isEmpty ? nil : report.note
    }
  }

  /// Go back to the app's own folder. Nothing is ever left without a library.
  func forget() {
    guard moving == nil else {
      message = "Still moving the library to the last folder — try again in a moment."
      return
    }
    // A read still in flight would otherwise land after this and point the app
    // back at the folder the user just walked away from.
    preparingToken = nil
    preparing = nil
    UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    UserDefaults.standard.removeObject(forKey: Self.pathKey)
    scoped?.stopAccessingSecurityScopedResource()
    scoped = nil
    message = nil
    Task { await PosterStore.shared.forget() }
    adoptOwnFolder()
  }

  func rescan() {
    let root = libraryURL
    let external = catalogue
    scanning = true
    message = nil
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        let local = CatalogIndex.load(root: root) ?? .empty
        let catalog = CatalogIndex.merged(primary: local, secondary: external)
        return LibraryScanner.scan(root: root, catalog: catalog)
      }.value
      // A scan of a folder the app has since left must not answer for the new
      // one: picking a folder while the app's own is still being read used to
      // leave the empty own folder's result showing.
      guard isSamePath(root, libraryURL) else { return }
      scan = result
      scanning = false
      if result.isEmpty, moving == nil {
        message = usingOwnFolder
          ? "Nothing here yet. A lesson fetched in Discover lands in this folder, and one copied into it from Files is read in place."
          : "No lessons found. Point the app at the folder that holds Courses, Videos and Commentaries."
      }
    }
  }

  private func attachSavedPath() -> Bool {
    guard let relative = UserDefaults.standard.string(forKey: Self.pathKey) else { return false }
    guard !relative.isEmpty else {
      adoptOwnFolder()
      return true
    }
    let url = documents.appendingPathComponent(relative, isDirectory: true)
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

  private func attach(
    _ url: URL,
    persist: Bool,
    scopeStarted: Bool = false,
    isCloud: Bool? = nil
  ) {
    let started = scopeStarted || url.startAccessingSecurityScopedResource()
    scoped = url
    rootURL = url
    rootName = displayName(for: url)
    isCloudRoot = isCloud ?? ((try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true)
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
