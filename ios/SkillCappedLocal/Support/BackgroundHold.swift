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
  private var lease: BackgroundLease?
  private let make: @MainActor (String) -> BackgroundLease

  init(make: @escaping @MainActor (String) -> BackgroundLease = { BackgroundLease($0) }) {
    self.make = make
  }

  /// Whether the app is actually being kept awake, not merely asked to be.
  var isHolding: Bool { lease?.isHolding == true }

  /// Take an assertion unless this hold has a live one already. A lease the system
  /// took back is replaced: the next part that settles is the moment to ask again.
  func renew(_ name: String) {
    guard !isHolding else { return }
    lease = make(name)
  }

  func end() {
    lease?.end()
    lease = nil
  }
}
