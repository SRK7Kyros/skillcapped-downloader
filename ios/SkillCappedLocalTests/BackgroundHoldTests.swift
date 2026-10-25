import UIKit
import XCTest
@testable import SkillCappedLocal

/// iOS gives the app around thirty seconds at a time and then takes it back, and
/// the lease object stays behind after it does. These pin the one thing that went
/// wrong on a device — a hold whose lease the system had already expired answered
/// "still holding", so every renewal was a no-op and the queue went back to one
/// window of parts per system wake — and the refusal that must not be retried on
/// every part.
@MainActor
final class BackgroundHoldTests: XCTestCase {
  /// UIKit's side of an assertion, played by the test so the expiry path — the one
  /// that cannot be triggered from an unhosted bundle — can be driven by hand.
  @MainActor
  private final class FakeAssertions: BackgroundAssertions {
    /// What a spent background budget looks like: `beginBackgroundTask` answers
    /// `.invalid` and there is no handler to run.
    var refuses = false
    private(set) var begun = 0
    private(set) var ended = 0
    private var expiries: [() -> Void] = []

    func begin(_ name: String, expired: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
      begun += 1
      guard !refuses else { return .invalid }
      expiries.append(expired)
      return UIBackgroundTaskIdentifier(rawValue: begun)
    }

    func end(_ token: UIBackgroundTaskIdentifier) {
      ended += 1
    }

    /// What iOS does when its time is up: run the handler, expect the token back.
    func expire() {
      expiries.last?()
    }
  }

  private func slot(_ fake: FakeAssertions, clock: @escaping @MainActor () -> Date) -> BackgroundHold {
    BackgroundHold(retryAfter: 10, now: clock) { name in
      BackgroundLease(name, assertions: fake)
    }
  }

  func testALeaseIsHoldingOnlyUntilTheSystemTakesItBack() {
    let fake = FakeAssertions()
    let lease = BackgroundLease("lesson", assertions: fake)
    XCTAssertTrue(lease.isHolding)
    XCTAssertEqual(fake.begun, 1)

    fake.expire()
    XCTAssertFalse(lease.isHolding, "an expired lease must not claim the app is awake")
    XCTAssertEqual(fake.ended, 1, "the expiration handler has to hand the token back")
  }

  func testAHoldRenewsALeaseTheSystemTookBack() {
    let fake = FakeAssertions()
    let held = slot(fake) { Date() }
    held.renew("lesson")
    XCTAssertTrue(held.isHolding)
    XCTAssertEqual(fake.begun, 1)

    fake.expire()
    XCTAssertFalse(held.isHolding)

    // The regression: this used to return here because the dead lease still
    // occupied the slot, so the app slept with most of the lesson to fetch.
    held.renew("lesson")
    XCTAssertTrue(held.isHolding)
    XCTAssertEqual(fake.begun, 2, "a lease iOS took back must be replaced, not kept")
  }

  func testAHoldKeepsALeaseThatIsStillLive() {
    let fake = FakeAssertions()
    let held = slot(fake) { Date() }
    held.renew("lesson")
    held.renew("lesson")
    held.renew("lesson")
    XCTAssertEqual(fake.begun, 1, "one hold needs one assertion")
  }

  func testARefusedGrantIsNotRetriedOnEveryPart() {
    let fake = FakeAssertions()
    fake.refuses = true
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let held = slot(fake) { clock }

    // The app is awake, so parts settle in a stream: eleven attempts a second would
    // each write a journal line and wipe the history that explains the refusal.
    for _ in 0..<20 { held.renew("lesson") }
    XCTAssertFalse(held.isHolding)
    XCTAssertEqual(fake.begun, 1, "a refusal is retried once per window, not once per part")

    clock = clock.addingTimeInterval(10.5)
    held.renew("lesson")
    XCTAssertEqual(fake.begun, 2, "the next window tries again")
  }

  func testAGrantThatWorksClearsTheRefusalThrottle() {
    let fake = FakeAssertions()
    fake.refuses = true
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let held = slot(fake) { clock }
    held.renew("lesson")
    XCTAssertFalse(held.isHolding)

    fake.refuses = false
    clock = clock.addingTimeInterval(11)
    held.renew("lesson")
    XCTAssertTrue(held.isHolding)

    // A finished lesson must not inherit a wait from an earlier refusal.
    held.end()
    held.renew("lesson")
    XCTAssertTrue(held.isHolding)
    XCTAssertEqual(fake.begun, 3)
  }

  func testEndingAHoldHandsTheTokenBackExactlyOnce() {
    let fake = FakeAssertions()
    let held = slot(fake) { Date() }
    held.renew("merge")
    held.end()
    XCTAssertFalse(held.isHolding)
    XCTAssertEqual(fake.ended, 1)

    held.end()
    XCTAssertEqual(fake.ended, 1, "a spent lease is not handed back twice")
  }

  func testAnExpiredGrantReportsHowLongItLasted() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let end = start.addingTimeInterval(31.4)
    XCTAssertEqual(BackgroundLease.seconds(since: start, now: end), "31.4")
  }
}
