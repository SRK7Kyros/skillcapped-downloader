import UIKit

/// A short extension to finish what is already running when the app leaves the
/// foreground — the system grants roughly thirty seconds.
///
/// A transfer itself does not need this: it runs in the system's own background
/// session and continues while the app is suspended. Merging the parts into one
/// stream and moving it into the library do need it, because that is ordinary
/// work in this process.
@MainActor
final class BackgroundLease {
  private var token: UIBackgroundTaskIdentifier = .invalid

  init(_ name: String) {
    token = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.end()
    }
  }

  func end() {
    guard token != .invalid else { return }
    UIApplication.shared.endBackgroundTask(token)
    token = .invalid
  }
}
