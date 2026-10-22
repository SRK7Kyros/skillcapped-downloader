import SwiftUI

/// One course from the catalogue: its lessons, what is already here, and one
/// button that queues everything that is not.
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
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header

        if lessons.isEmpty {
          Text("This course has no published lessons in the catalogue — the site lists it but not its videos.")
            .font(.footnote)
            .foregroundStyle(Palette.inkDim)
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
          .padding(.top, 6)
        }
      }
      .padding(.bottom, 36)
    }
    .background(Palette.bg.ignoresSafeArea())
    .navigationTitle(course.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          downloads.enqueue(missing.map { $0.downloadRequest(courseTitle: course.title) }, quality: nil)
        } label: {
          Label("Download missing", systemImage: "arrow.down.circle")
        }
        .disabled(missing.isEmpty)
        .accessibilityLabel("Download missing lessons")
      }
    }
  }

  private var header: some View {
    ZStack(alignment: .bottomLeading) {
      RemotePoster(url: course.thumbURL, seed: course.title)
        .frame(height: 208)

      LinearGradient(
        colors: [.clear, Palette.bg.opacity(0.55), Palette.bg],
        startPoint: .top,
        endPoint: .bottom
      )

      VStack(alignment: .leading, spacing: 8) {
        if !course.role.isEmpty {
          Text(Format.roleLabel(course.role))
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Palette.bg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.brand, in: Capsule())
        }
        Text(course.title)
          .font(.title2.weight(.bold))
          .foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 6) {
          Text(Format.count(lessons.count, "lesson", "lessons"))
          if !lessons.isEmpty {
            Text("·")
            Text("\(downloadedCount) on disk")
          }
          if let date = Format.date(course.date) {
            Text("·")
            Text(date)
          }
        }
        .font(.caption)
        .foregroundStyle(Palette.inkDim)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 12)
    }
    .frame(height: 208)
  }

  private func act(on item: CatalogItem) {
    if let lesson = localLesson(for: item.id) {
      player.play(lesson)
      return
    }
    guard downloads.task(for: item.id) == nil, !downloads.isReady(item.id) else { return }
    downloads.enqueue([item.downloadRequest(courseTitle: course.title)], quality: nil)
  }

  private func localLesson(for id: String) -> Lesson? {
    guard let scan = store.scan else { return nil }
    for item in scan.courses {
      if let lesson = item.lessons.first(where: { $0.itemId == id }) { return lesson }
    }
    return scan.videos.first { $0.itemId == id } ?? scan.commentaries.first { $0.itemId == id }
  }
}
