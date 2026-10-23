import SwiftUI

/// One course from the catalogue: its lessons, what is already here, and one
/// pill that plays what this phone has or fetches what it does not — the same
/// page the library's course opens, with the catalogue's rows in it.
struct DiscoverCourseView: View {
  let course: CatalogItem

  @EnvironmentObject private var catalogue: CatalogueStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var player: PlayerCoordinator

  private var onDisk: Set<String> { store.scan?.onDiskIds ?? [] }

  private var lessons: [CatalogItem] {
    catalogue.catalog?.lessons(of: course) ?? []
  }

  private var missing: [CatalogItem] {
    lessons.filter { item in
      !onDisk.contains(item.id) && !downloads.isReady(item.id) && downloads.task(for: item.id) == nil
    }
  }

  private var downloadedCount: Int {
    lessons.reduce(0) { count, item in
      (onDisk.contains(item.id) || downloads.isReady(item.id)) ? count + 1 : count
    }
  }

  var body: some View {
    GeometryReader { proxy in
      if CourseLayout.isSideBySide(proxy.size) {
        sideBySide(proxy.size)
      } else {
        stacked(proxy.size)
      }
    }
    .background(Palette.bg.ignoresSafeArea())
    .navigationTitle(course.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          downloadMissing()
        } label: {
          Label("Download missing", systemImage: "arrow.down.circle")
        }
        .disabled(missing.isEmpty)
        .accessibilityLabel("Download missing lessons")
      }
    }
  }

  // MARK: - Landscape: poster pinned left, words and lessons on the right

  private func sideBySide(_ size: CGSize) -> some View {
    let side = CourseLayout.posterColumn(size: size, ratio: PosterShape.portrait)
    return HStack(alignment: .top, spacing: 0) {
      poster(fill: CGSize(width: side, height: size.height), target: 900)

      Rectangle()
        .fill(Palette.line)
        .frame(width: 1)

      VStack(spacing: 0) {
        hero(pinned: true)
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 10)

        Rectangle()
          .fill(Palette.line)
          .frame(height: 1)

        lessonList
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  // MARK: - Portrait: a small poster beside the words, lessons underneath

  private func stacked(_ size: CGSize) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        poster(width: CourseLayout.heroWidth(for: size.width), target: 420)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(Palette.line, lineWidth: 1)
          }

        hero(pinned: false)
      }
      .padding(16)

      Rectangle()
        .fill(Palette.line)
        .frame(height: 1)

      lessonList
    }
  }

  // MARK: - Poster

  /// The catalogue's art at the course window, whole.
  private func poster(fill: CGSize? = nil, width: CGFloat? = nil, target: CGFloat) -> some View {
    PosterArt(
      url: course.thumbURL,
      seed: course.title,
      fallback: PosterShape.portraitArt,
      window: PosterShape.portrait,
      width: width,
      fill: fill,
      targetWidth: target
    )
  }

  // MARK: - Words

  private func hero(pinned: Bool) -> some View {
    CourseHero(role: course.role, title: course.title, meta: meta, pinned: pinned) {
      heroAction(compact: pinned)
    }
  }

  /// *Play* when a lesson of this course is already here, the download when none
  /// is — the one thing worth doing from this page, in the one shape both course
  /// pages use.
  @ViewBuilder private func heroAction(compact: Bool) -> some View {
    if let first = localLessons.first {
      Button {
        player.play(first, in: localLessons)
      } label: {
        CoursePill(title: "Play", systemImage: "play.fill", compact: compact)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Play \(course.title) from the first lesson here")
    } else if !missing.isEmpty {
      Button {
        downloadMissing()
      } label: {
        CoursePill(title: "Download", systemImage: "arrow.down.circle.fill", compact: compact)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Download the missing lessons of \(course.title)")
    }
  }

  private var meta: String {
    var parts: [String] = []
    if lessons.isEmpty {
      parts.append("No published lessons")
    } else {
      parts.append(Format.count(lessons.count, "lesson", "lessons"))
      if downloadedCount > 0 { parts.append("\(downloadedCount) on disk") }
    }
    if let date = Format.date(course.date) { parts.append(date) }
    return parts.joined(separator: " · ")
  }

  // MARK: - The list that scrolls

  private var lessonList: some View {
    ScrollView {
      if lessons.isEmpty {
        Text("This course has no published lessons in the catalogue — the site lists it but not its videos.")
          .font(.footnote)
          .foregroundStyle(Palette.inkDim)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.top, 16)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(lessons.enumerated()), id: \.element.id) { index, item in
            CatalogLessonRow(
              item: item,
              index: index + 1,
              state: CatalogState.of(item.id, downloads: downloads, onDisk: onDisk)
            ) {
              act(on: item)
            }
            if item.id != lessons.last?.id {
              Divider().overlay(Palette.line)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 36)
      }
    }
  }

  // MARK: - Actions

  private func downloadMissing() {
    downloads.enqueue(missing.map { $0.downloadRequest(courseTitle: course.title) }, quality: nil)
  }

  private func act(on item: CatalogItem) {
    if let lesson = localLesson(for: item.id) {
      player.play(lesson, in: localLessons)
      return
    }
    guard downloads.task(for: item.id) == nil, !downloads.isReady(item.id) else { return }
    downloads.enqueue([item.downloadRequest(courseTitle: course.title)], quality: nil)
  }

  /// The course's lessons this phone can play, in the catalogue's order.
  private var localLessons: [Lesson] {
    lessons.compactMap { localLesson(for: $0.id) }
  }

  private func localLesson(for id: String) -> Lesson? {
    guard let scan = store.scan else { return nil }
    for item in scan.courses {
      if let lesson = item.lessons.first(where: { $0.itemId == id }) { return lesson }
    }
    return scan.videos.first { $0.itemId == id } ?? scan.commentaries.first { $0.itemId == id }
  }
}
