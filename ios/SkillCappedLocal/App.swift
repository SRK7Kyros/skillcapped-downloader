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
        .onChange(of: scenePhase) { _, _ in
          // Both directions matter, and leaving matters most: the lesson in flight
          // is refilled by this process, so the assertion that keeps it awake has
          // to be taken as the app goes away — waiting for a transfer to wake it
          // again is what made a queue crawl. Coming back is the other half: if the
          // system stopped waking the app, a lesson left queued picks up here.
          downloads.wake()
        }
    }
  }
}
