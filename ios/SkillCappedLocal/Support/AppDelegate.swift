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
    BackgroundTransfer.shared.onUnattendedPart = {
      Task { @MainActor in DownloadManager.shared.wake() }
    }
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
    BackgroundTransfer.shared.store(eventsCompletion: completionHandler)
  }
}
