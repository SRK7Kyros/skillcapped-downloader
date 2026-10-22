import SwiftUI

/// The site's own catalogue, read straight from its public documents — no
/// server, no account. Anything here can be pulled onto the phone.
struct DiscoverView: View {
  @EnvironmentObject private var catalogue: CatalogueStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var player: PlayerCoordinator

  @State private var kind = "course"
  @State private var role = ""
  @State private var query = ""

  private var onDisk: Set<String> { store.scan?.onDiskIds ?? [] }

  var body: some View {
    NavigationStack {
      Group {
        if let catalog = catalogue.catalog {
          content(catalog)
        } else if let error = catalogue.error {
          failure(error)
        } else {
          ProgressView("Fetching the catalogue…")
            .font(.footnote)
            .foregroundStyle(Palette.inkDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(Palette.bg.ignoresSafeArea())
      .navigationTitle("Discover")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: CatalogItem.self) { course in
        DiscoverCourseView(course: course)
      }
      .searchable(
        text: $query,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Search the catalogue"
      )
      .refreshable { catalogue.refresh() }
      .task { catalogue.load() }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            catalogue.refresh()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(catalogue.loading)
          .accessibilityLabel("Refresh catalogue")
        }
      }
    }
  }

  // MARK: - Content

  @ViewBuilder
  private func content(_ catalog: RemoteCatalog) -> some View {
    let courses = matching(catalog.items(kind: "course"))
    let videos = matching(catalog.items(kind: "video"))
    let commentaries = matching(catalog.items(kind: "commentary"))

    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        summary(catalog)
        kindPicker

        let roles = roles(of: catalog)
        if !roles.isEmpty { roleChips(roles) }

        switch kind {
        case "course":
          if courses.isEmpty {
            empty()
          } else {
            section("Courses", detail: Format.count(courses.count, "course", "courses"))
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 158, maximum: 240), spacing: 12, alignment: .top)],
              alignment: .leading,
              spacing: 12
            ) {
              ForEach(courses) { course in
                NavigationLink(value: course) {
                  CatalogCourseCard(
                    item: course,
                    downloaded: downloadedCount(course, in: catalog),
                    total: course.lessonIds.count
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }
        case "video":
          if videos.isEmpty {
            empty()
          } else {
            section("Videos", detail: Format.count(videos.count, "video", "videos"))
            lessonList(videos)
          }
        default:
          if commentaries.isEmpty {
            empty()
          } else {
            section("Commentaries", detail: Format.count(commentaries.count, "recording", "recordings"))
            lessonList(commentaries)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 4)
      .padding(.bottom, 36)
    }
  }

  private var kindPicker: some View {
    Picker("Kind", selection: $kind) {
      Text("Courses").tag("course")
      Text("Videos").tag("video")
      Text("Commentaries").tag("commentary")
    }
    .pickerStyle(.segmented)
  }

  private func summary(_ catalog: RemoteCatalog) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(catalog.season.isEmpty ? "SkillCapped catalogue" : catalog.season)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Palette.inkDim)
      Text("\(Format.count(catalog.items.count, "entry", "entries"))"
           + (catalog.patch.isEmpty ? "" : " · patch \(catalog.patch)")
           + (catalogue.loading ? " · refreshing…" : ""))
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
    }
  }

  private func section(_ title: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.headline)
        .foregroundStyle(Palette.ink)
      Spacer()
      Text(detail)
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
    }
  }

  private func roleChips(_ roles: [String]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip("All roles", value: "")
        ForEach(roles, id: \.self) { name in
          chip(Format.roleLabel(name), value: name)
        }
      }
      .padding(.vertical, 1)
    }
  }

  private func chip(_ label: String, value: String) -> some View {
    Button {
      role = value
    } label: {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(role == value ? Palette.bg : Palette.inkDim)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(role == value ? Palette.brand : Palette.surface, in: Capsule())
        .overlay {
          Capsule().stroke(role == value ? Color.clear : Palette.line, lineWidth: 1)
        }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private func lessonList(_ items: [CatalogItem]) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(items) { item in
        CatalogLessonRow(
          item: item,
          state: CatalogState.of(item.id, downloads: downloads, onDisk: onDisk)
        ) {
          act(on: item)
        }
        if item.id != items.last?.id {
          Divider().overlay(Palette.line)
        }
      }
    }
  }

  private func empty() -> some View {
    Text(query.isEmpty ? "Nothing to show here yet." : "Nothing matches “\(query)”.")
      .font(.subheadline)
      .foregroundStyle(Palette.inkDim)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 8)
  }

  private func failure(_ message: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "wifi.exclamationmark")
        .font(.largeTitle)
        .foregroundStyle(Palette.inkFaint)
      Text(message)
        .font(.footnote)
        .foregroundStyle(Palette.inkDim)
        .multilineTextAlignment(.center)
      Button("Try again") { catalogue.refresh() }
        .buttonStyle(.borderedProminent)
        .tint(Palette.brand)
        .foregroundStyle(Palette.bg)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Actions

  private func act(on item: CatalogItem) {
    if let lesson = localLesson(for: item.id) {
      player.play(lesson)
      return
    }
    guard !downloads.isReady(item.id) else { return }
    downloads.enqueue([item.downloadRequest(courseTitle: nil)], quality: nil)
  }

  private func localLesson(for id: String) -> Lesson? {
    guard let scan = store.scan else { return nil }
    for course in scan.courses {
      if let lesson = course.lessons.first(where: { $0.itemId == id }) { return lesson }
    }
    return scan.videos.first { $0.itemId == id } ?? scan.commentaries.first { $0.itemId == id }
  }

  // MARK: - Filtering

  private func matching(_ items: [CatalogItem]) -> [CatalogItem] {
    items.filter { item in
      if !role.isEmpty, item.role != role { return false }
      return Search.matches(item.title + " " + item.role + " " + item.category, query: query)
    }
  }

  private func roles(of catalog: RemoteCatalog) -> [String] {
    var seen: Set<String> = []
    var found: [String] = []
    for item in catalog.items where !item.role.isEmpty && item.role != "all" {
      if seen.insert(item.role).inserted { found.append(item.role) }
    }
    return found.sorted()
  }

  private func downloadedCount(_ course: CatalogItem, in catalog: RemoteCatalog) -> Int {
    course.lessonIds.reduce(0) { count, id in
      (onDisk.contains(id) || downloads.isReady(id)) ? count + 1 : count
    }
  }
}
