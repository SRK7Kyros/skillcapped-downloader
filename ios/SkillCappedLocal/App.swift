import SwiftUI

@main
@MainActor
struct SkillCappedLocalApp: App {
  @StateObject private var store = LibraryStore()
  @StateObject private var player = PlayerCoordinator()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .environmentObject(player)
        .preferredColorScheme(.dark)
        .tint(Palette.brand)
    }
  }
}
