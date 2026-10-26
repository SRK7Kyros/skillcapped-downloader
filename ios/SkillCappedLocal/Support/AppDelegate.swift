import UIKit

/// The one thing SwiftUI cannot do itself: own the completion handler the system
/// hands over when it wakes the app to deliver a background transfer.
///
/// Nothing here touches the UI. A relaunch in the background has no scene, so the
/// download queue is reached through its shared instance rather than through a
/// view's environment.
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BackgroundJournal.shared.record("launch (\(Self.name(of: application.applicationState)))")
    if application.backgroundRefreshStatus == .denied {
      // The one reason no transfer event can ever reach this app. iOS will not
      // relaunch a suspended app for a background session while Background App
      // Refresh is off, so a lesson handed over here is never handed back and the
      // queue stops on it with nothing in the app able to say why.
      BackgroundJournal.shared.record(
        "background app refresh is OFF — iOS will not wake the app for transfers"
      )
    }
    BackgroundTransfer.shared.onUnattendedPart = {
      BackgroundJournal.shared.record("part landed with nobody waiting")
      Task { @MainActor in DownloadManager.shared.wake() }
    }
    BackgroundTransfer.shared.onWentIdle = {
      Task { @MainActor in DownloadManager.shared.transferWentIdle() }
    }
    // Registering is a launch-time job: the system hands a continued-processing
    // task back only if its identifier was registered before launch finished.
    ContinuedProcessing.shared.register()
    return true
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == BackgroundTransfer.identifier else {
      completionHandler()
      return
    }
    BackgroundJournal.shared.record("transfer events arrived")
    BackgroundTransfer.shared.store(eventsCompletion: completionHandler)
  }

  private static func name(of state: UIApplication.State) -> String {
    switch state {
    case .active: return "foreground"
    case .background: return "background"
    case .inactive: return "inactive"
    @unknown default: return "unknown"
    }
  }
}
