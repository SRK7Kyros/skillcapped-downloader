import SwiftUI

@main
@MainActor
struct SkillCappedLocalApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @Environment(\.scenePhase) private var scenePhase

  @StateObject private var store = LibraryStore()
  @StateObject private var player = PlayerCoordinator()
  @StateObject private var prefs = PreferencesStore()
  @StateObject private var catalogue = CatalogueStore()
  @StateObject private var progress = ProgressStore()
  @StateObject private var downloads = DownloadManager.shared

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .environmentObject(player)
        .environmentObject(prefs)
        .environmentObject(catalogue)
        .environmentObject(progress)
        .environmentObject(downloads)
        .preferredColorScheme(.dark)
        .tint(Palette.brand)
        .onChange(of: scenePhase) { _, phase in
          // Coming back is the one moment the queue can be restarted by hand. If the
          // system stopped waking the app for its transfers, a lesson left queued
          // picks up from here instead of waiting for a relaunch.
          guard phase == .active else { return }
          downloads.wake()
        }
    }
  }
}
