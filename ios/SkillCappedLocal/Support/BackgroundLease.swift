import UIKit

/// A short extension to finish what is already running when the app leaves the
/// foreground — the system grants roughly thirty seconds.
///
/// A transfer itself does not need this: it runs in the system's own background
/// session and continues while the app is suspended. Merging the parts into one
/// stream, moving it into the library, and reading a manifest between two lessons
/// do need it, because that is ordinary work in this process.
@MainActor
final class BackgroundLease {
  private let name: String
  private var token: UIBackgroundTaskIdentifier = .invalid

  init(_ name: String) {
    self.name = name
    token = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      BackgroundJournal.shared.record("lease expired \(name)")
      self?.end()
    }
    BackgroundJournal.shared.record(token == .invalid ? "lease refused \(name)" : "lease +\(name)")
  }

  func end() {
    guard token != .invalid else { return }
    UIApplication.shared.endBackgroundTask(token)
    token = .invalid
    BackgroundJournal.shared.record("lease -\(name)")
  }
}
