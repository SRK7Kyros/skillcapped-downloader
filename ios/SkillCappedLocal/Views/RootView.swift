import SwiftUI

struct RootView: View {
  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var player: PlayerCoordinator
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var prefs: PreferencesStore
  @EnvironmentObject private var catalogue: CatalogueStore

  @State private var tab: Tab = .library
  @State private var picking = false
  @State private var settings = false

  private enum Tab: Hashable {
    case library
    case discover
    case downloads
  }

  var body: some View {
    TabView(selection: $tab) {
      library
        .tabItem { Label("Library", systemImage: "books.vertical") }
        .tag(Tab.library)

      DiscoverView()
        .tabItem { Label("Discover", systemImage: "sparkles") }
        .tag(Tab.discover)

      DownloadsView()
        .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
        .badge(downloads.activeCount)
        .tag(Tab.downloads)
    }
    .tint(Palette.brand)
    .onOpenURL { url in
      store.choose(url)
    }
    .sheet(isPresented: $picking) {
      LibraryLocationView()
    }
    .sheet(isPresented: $settings) {
      SettingsView()
    }
    .fullScreenCover(item: $player.lesson) { lesson in
      PlayerScreen(lesson: lesson)
    }
    .onAppear {
      sync()
      catalogue.load()
      store.adopt(catalog: catalogue.index)
    }
    .onChange(of: catalogue.catalog?.generatedAt) { _, _ in
      store.adopt(catalog: catalogue.index)
    }
    .onChange(of: store.rootURL) { _, _ in sync() }
    .onChange(of: prefs.qualityPriority) { _, order in downloads.qualityPriority = order }
  }

  /// Downloads land in the library the app is pointed at, so a finished lesson
  /// is where the browser already looks.
  private func sync() {
    store.beforeMove = { [downloads] in await downloads.hold() }
    store.afterMove = { [downloads, store] from, to in
      downloads.relocate(from: from, to: to)
      downloads.root = store.downloadRoot
      downloads.release()
    }
    guard store.moving == nil else { return }
    downloads.root = store.downloadRoot
    downloads.qualityPriority = prefs.qualityPriority
    downloads.onChange = { [store] in store.rescan() }
  }

  private var library: some View {
    NavigationStack {
      content
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
          if let moving = store.moving {
            MoveBanner(move: moving)
          } else if let name = store.preparing {
            ReadBanner(name: name, stop: { store.stopPreparing() })
          }
        }
        .navigationTitle(store.rootName ?? "SkillCapped Local")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Course.self) { course in
          CourseView(course: course)
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              picking = true
            } label: {
              Image(systemName: "folder")
            }
            .accessibilityLabel("Library folder")
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              settings = true
            } label: {
              Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Library settings")
          }
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let scan = store.scan, !scan.isEmpty {
      BrowseView(scan: scan)
    } else if store.scanning {
      VStack(spacing: 12) {
        ProgressView()
          .tint(Palette.brand)
        Text("Reading the folder…")
          .font(.footnote)
          .foregroundStyle(Palette.inkDim)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      WelcomeView(pick: { picking = true }, message: store.message, folder: store.rootName)
    }
  }
}

private struct MoveBanner: View {
  let move: LibraryMigration.Progress

  var body: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)
        .tint(Palette.brand)
      Text(move.label)
        .font(.caption)
        .foregroundStyle(Palette.inkDim)
      Spacer(minLength: 0)
      if move.bytes > 0 {
        Text(Format.bytes(move.bytes))
          .font(.caption.monospacedDigit())
          .foregroundStyle(Palette.inkFaint)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Palette.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Palette.line).frame(height: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

/// A folder is being read — the step after the picker's **Open** that can take
/// as long as the file provider likes. It says what it is waiting for, and it
/// can be abandoned, so the app is never stuck behind it.
private struct ReadBanner: View {
  let name: String
  let stop: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)
        .tint(Palette.brand)
      Text("Reading \(name)…")
        .font(.caption)
        .foregroundStyle(Palette.inkDim)
        .lineLimit(1)
      Spacer(minLength: 0)
      Button("Stop", action: stop)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.brand)
        .accessibilityHint("Leaves the library where it is")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Palette.surface)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Palette.line).frame(height: 1)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct WelcomeView: View {
  let pick: () -> Void
  let message: String?
  let folder: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Spacer(minLength: 0)

      Text("Your lessons, offline.")
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(Palette.ink)

      Text("Lessons live in the app's own folder — Files › \(FilesPlace.ownFolder) — or in whichever folder you choose, iCloud Drive included. The app reads it in place: nothing is copied again by the app.")
        .font(.subheadline)
        .foregroundStyle(Palette.inkDim)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 10) {
        bullet("play.rectangle.fill", "Native playback", "AVPlayer, with picture in picture, AirPlay and resume.")
        bullet("arrow.down.circle.fill", "Download in the app", "Discover the catalogue and pull a course straight onto the phone.")
        bullet("icloud.fill", "Cloud or local", "A folder in iCloud Drive is read the same way; a lesson is fetched only when you play it.")
      }

      if let folder {
        Text("Last folder: \(folder)")
          .font(.caption)
          .foregroundStyle(Palette.inkFaint)
      }

      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(Palette.warn)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(action: pick) {
        Label("Choose a folder", systemImage: "folder.badge.plus")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(Palette.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .foregroundStyle(Palette.bg)
      }
      .buttonStyle(.plain)

      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func bullet(_ glyph: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: glyph)
        .font(.footnote)
        .foregroundStyle(Palette.brand)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Palette.ink)
        Text(detail)
          .font(.caption)
          .foregroundStyle(Palette.inkFaint)
      }
    }
  }
}
