import UIKit

/// How an assertion is taken and handed back. UIKit in the app; a test supplies its
/// own, because the expiry path is exactly the one that goes unnoticed on a device
/// and cannot be driven from an unhosted test bundle.
@MainActor
protocol BackgroundAssertions: AnyObject {
  func begin(_ name: String, expired: @escaping () -> Void) -> UIBackgroundTaskIdentifier
  func end(_ token: UIBackgroundTaskIdentifier)
}

/// The real one: the system runs `expired` when its time is up.
@MainActor
final class SystemAssertions: BackgroundAssertions {
  static let shared = SystemAssertions()

  func begin(_ name: String, expired: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
    UIApplication.shared.beginBackgroundTask(withName: name) { expired() }
  }

  func end(_ token: UIBackgroundTaskIdentifier) {
    UIApplication.shared.endBackgroundTask(token)
  }
}

/// A named hold on the app's background time — the system grants roughly thirty
/// seconds at a time.
///
/// A transfer itself does not need this: it runs in the system's own background
/// session and continues while the app is suspended. Merging the parts into one
/// stream, moving it into the library, and handing over the next window of parts
/// do need it, because that is ordinary work in this process.
///
/// iOS takes the assertion back on its own schedule: the expiration handler runs,
/// the token dies, and **this object stays behind**. So `isHolding` — not "is there
/// a lease?" — is the only honest answer to "am I still keeping the app awake?".
/// Asking the other question is what stopped a 380-part lesson at 208 parts: the
/// slot stayed occupied by a lease the system had already taken back, every renewal
/// returned at once, the app slept, and the rest of the lesson arrived one window
/// per system wake instead of one part per 88 ms.
@MainActor
final class BackgroundLease {
  private let name: String
  private let assertions: any BackgroundAssertions
  private let started = Date()
  private var token: UIBackgroundTaskIdentifier = .invalid

  /// Whether the system is still honouring this assertion.
  var isHolding: Bool { token != .invalid }

  init(_ name: String, assertions: (any BackgroundAssertions)? = nil) {
    self.name = name
    let chosen = assertions ?? SystemAssertions.shared
    self.assertions = chosen
    token = chosen.begin(name) { [weak self] in
      self?.expire()
    }
    BackgroundJournal.shared.record(isHolding ? "lease +\(name)" : "lease refused \(name)")
  }

  /// iOS wants its time back: the handler fires, the assertion must be ended, and
  /// the grant's real length is the number that decides whether a renewal is worth
  /// taking at all (a grant that lasts a second means the app's background budget
  /// is spent and the queue has to fall back to what the system fetches alone).
  private func expire() {
    guard token != .invalid else { return }
    BackgroundJournal.shared.record(
      "lease expired \(name) after \(BackgroundLease.seconds(since: started)) s"
    )
    end()
  }

  func end() {
    guard token != .invalid else { return }
    let spent = token
    token = .invalid
    assertions.end(spent)
    BackgroundJournal.shared.record("lease -\(name)")
  }

  nonisolated static func seconds(since start: Date, now: Date = Date()) -> String {
    String(format: "%.1f", now.timeIntervalSince(start))
  }
}
