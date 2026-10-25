import SwiftUI

@main
@MainActor
struct SkillCappedLocalApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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
    }
  }
}
