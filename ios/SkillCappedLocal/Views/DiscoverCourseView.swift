import SwiftUI

/// One course from the catalogue.
///
/// The screen itself is `CoursePage` — the same page the library's course opens.
/// This is the catalogue's source for it: the site's lessons, joined with the
/// files this phone already holds, so a row that has been downloaded reads
/// exactly like the library's row for it.
struct DiscoverCourseView: View {
  let course: CatalogItem

  @EnvironmentObject private var catalogue: CatalogueStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var progress: ProgressStore

  private var lessons: [CatalogItem] {
    catalogue.catalog?.lessons(of: course) ?? []
  }

  private var onDisk: Set<String> { store.scan?.onDiskIds ?? [] }

  var body: some View {
    CoursePage(
      page: .catalogue(
        course,
        lessons: lessons,
        scan: store.scan,
        state: { id in CatalogState.of(id, downloads: downloads, onDisk: onDisk) },
        progress: { key in progress.fraction(for: key) }
      )
    )
  }
}
