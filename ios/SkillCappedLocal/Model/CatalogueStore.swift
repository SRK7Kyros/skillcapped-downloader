import Foundation

/// The catalogue as the site publishes it, kept warm while the app runs.
///
/// Browse works offline: the last successful fetch is cached on disk, and a
/// failed refresh falls back to it instead of emptying the screen.
@MainActor
final class CatalogueStore: ObservableObject {
  @Published private(set) var catalog: RemoteCatalog?
  @Published private(set) var loading = false
  @Published private(set) var error: String?

  private var task: Task<Void, Never>?

  var index: CatalogIndex { catalog?.index ?? .empty }

  /// Load once per launch unless asked to refresh; the service decides whether
  /// its own copy is still young enough to skip the network.
  func load(force: Bool = false) {
    guard task == nil else { return }
    if !force, catalog != nil { return }
    loading = true
    error = nil
    task = Task { [weak self] in
      do {
        let catalog = try await CatalogService.load(force: force)
        self?.apply(catalog)
      } catch {
        self?.fail(error)
      }
    }
  }

  func refresh() {
    load(force: true)
  }

  func course(_ id: String) -> CatalogItem? {
    catalog?.course(id)
  }

  private func apply(_ catalog: RemoteCatalog) {
    self.catalog = catalog
    loading = false
    error = nil
    task = nil
  }

  private func fail(_ error: Error) {
    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    loading = false
    task = nil
  }
}

extension CatalogItem {
  /// What the queue needs to fetch this row. A lesson inside a course inherits
  /// the course's title so both downloaders write the same folder.
  func downloadRequest(courseTitle: String? = nil) -> DownloadRequest {
    DownloadRequest(
      uuid: id,
      title: title,
      kind: kind,
      role: role,
      category: category,
      courseTitle: self.courseTitle ?? courseTitle,
      durationSec: durationSec
    )
  }
}
