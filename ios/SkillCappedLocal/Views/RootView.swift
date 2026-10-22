import SwiftUI

struct RootView: View {
  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var player: PlayerCoordinator

  @State private var picking = false
  @State private var settings = false

  var body: some View {
    NavigationStack {
      content
        .background(Palette.bg.ignoresSafeArea())
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
            .disabled(!store.hasFolder)
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

      Text("Copy the folder the downloader writes to — the one holding Courses, Videos and Commentaries — into this app's folder in Files (On My iPhone › SkillCapped Local). The app reads it in place: nothing is copied again by the app, and it never downloads anything.")
        .font(.subheadline)
        .foregroundStyle(Palette.inkDim)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 10) {
        bullet("play.rectangle.fill", "Native playback", "AVPlayer, with picture in picture, AirPlay and resume.")
        bullet("photo.fill", "Real cover art", "A frame of each lesson, cached on the phone.")
        bullet("internaldrive.fill", "Stays local", "No network calls at all.")
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
        Label("Choose library folder", systemImage: "folder.badge.plus")
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
