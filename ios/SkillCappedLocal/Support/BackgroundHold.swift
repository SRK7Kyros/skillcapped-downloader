import Foundation

/// The queue's hold on the app's background time, one per kind of work.
///
/// A hold outlives the assertion iOS gave it: the lease object stays here after the
/// system takes its time back, so `renew` asks the lease whether it is *still*
/// holding rather than whether the slot is empty. That difference is the whole
/// point — a dead lease that keeps its slot makes every renewal a no-op, which is
/// how a lesson went back to one window per system wake while this process believed
/// it was awake.
@MainActor
final class BackgroundHold {
  /// Ten seconds: retrying a refusal costs nothing, but retrying it on *every part*
  /// — parts settle about eleven times a second while the app is awake — would fill
  /// the journal with refusals and wipe the history that explains them. Nothing runs
  /// while the app is suspended, so the wait cannot slow a sleeping queue down.
  nonisolated static let defaultRetryAfter: TimeInterval = 10

  private var lease: BackgroundLease?
  /// When the system last refused an assertion, so a refusal is retried once per
  /// window rather than once per part.
  private var refusedAt: Date?
  private let retryAfter: TimeInterval
  private let now: @MainActor () -> Date
  private let make: @MainActor (String) -> BackgroundLease

  init(
    retryAfter: TimeInterval = BackgroundHold.defaultRetryAfter,
    now: @escaping @MainActor () -> Date = { Date() },
    make: @escaping @MainActor (String) -> BackgroundLease = { BackgroundLease($0) }
  ) {
    self.retryAfter = retryAfter
    self.now = now
    self.make = make
  }

  /// Whether the app is actually being kept awake, not merely asked to be.
  var isHolding: Bool { lease?.isHolding == true }

  /// Take an assertion unless this hold has a live one already. A lease the system
  /// took back is replaced: the next part that settles is the moment to ask again.
  func renew(_ name: String) {
    guard !isHolding else { return }
    if let refusedAt, now().timeIntervalSince(refusedAt) < retryAfter { return }
    lease = make(name)
    // Only a refusal is worth waiting on; a lease that works clears the mark, so
    // the next lesson takes its assertion at once.
    refusedAt = isHolding ? nil : now()
  }

  func end() {
    lease?.end()
    lease = nil
  }
}
