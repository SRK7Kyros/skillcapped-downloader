import XCTest
@testable import SkillCappedLocal

final class WatchProgressMathTests: XCTestCase {
  func testFractionIsClamped() {
    XCTAssertEqual(WatchProgressMath.fraction(position: 0, duration: 600), 0)
    XCTAssertEqual(WatchProgressMath.fraction(position: 300, duration: 600), 0.5)
    XCTAssertEqual(WatchProgressMath.fraction(position: 900, duration: 600), 1)
  }

  func testFractionWithoutADurationIsZero() {
    XCTAssertEqual(WatchProgressMath.fraction(position: 120, duration: 0), 0)
  }

  func testAlmostTheEndIsTheEnd() {
    XCTAssertTrue(WatchProgressMath.isComplete(position: 590, duration: 600))
    XCTAssertFalse(WatchProgressMath.isComplete(position: 400, duration: 600))
  }

  func testAnUnknownDurationIsNeverComplete() {
    XCTAssertFalse(WatchProgressMath.isComplete(position: 590, duration: 0))
  }

  func testResumeSkipsTheFirstFewSeconds() {
    XCTAssertFalse(WatchProgressMath.shouldResume(position: 3, duration: 600))
    XCTAssertTrue(WatchProgressMath.shouldResume(position: 30, duration: 600))
  }

  func testResumeSkipsAFinishedLesson() {
    XCTAssertFalse(WatchProgressMath.shouldResume(position: 595, duration: 600))
  }
}

@MainActor
final class ProgressStoreTests: XCTestCase {
  override func setUp() async throws {
    JSONFile.remove(JSONFile.url("progress"))
  }

  func testRecordingALessonRemembersItsPosition() {
    let store = ProgressStore()
    store.record(key: "v1", position: 120, duration: 600)
    XCTAssertEqual(store.progress(for: "v1")?.position, 120)
    XCTAssertEqual(store.fraction(for: "v1") ?? 0, 0.2, accuracy: 0.0001)
  }

  func testAZeroPositionIsNotWorthStoring() {
    let store = ProgressStore()
    store.record(key: "v1", position: 0, duration: 600)
    XCTAssertNil(store.progress(for: "v1"))
  }

  func testReachingTheEndMarksTheLessonComplete() {
    let store = ProgressStore()
    store.record(key: "v1", position: 598, duration: 600)
    XCTAssertTrue(store.isComplete("v1"))
    XCTAssertEqual(store.fraction(for: "v1") ?? 0, 0.9966, accuracy: 0.0001)
  }

  func testAMissingDurationKeepsTheOneAlreadyKnown() {
    let store = ProgressStore()
    store.record(key: "v1", position: 120, duration: 600)
    store.record(key: "v1", position: 240, duration: 0)
    XCTAssertEqual(store.progress(for: "v1")?.duration, 600)
    XCTAssertEqual(store.fraction(for: "v1") ?? 0, 0.4, accuracy: 0.0001)
  }

  func testCompletionIsSticky() {
    let store = ProgressStore()
    store.markCompleted(key: "v1", duration: 600)
    store.record(key: "v1", position: 10, duration: 600)
    XCTAssertTrue(store.isComplete("v1"))
  }

  func testContinueWatchingIsNewestFirstAndSkipsFinishedLessons() {
    let store = ProgressStore()
    store.record(key: "a", position: 120, duration: 600)
    store.record(key: "b", position: 120, duration: 600)
    store.markCompleted(key: "c", duration: 600)
    store.record(key: "d", position: 2, duration: 600)
    XCTAssertEqual(store.recentKeys(), ["b", "a"])
  }

  func testMarkCompletedStoresTheEndPosition() {
    let store = ProgressStore()
    store.markCompleted(key: "v1", duration: 600)
    XCTAssertEqual(store.progress(for: "v1")?.position, 600)
  }

  func testClearForgetsALesson() {
    let store = ProgressStore()
    store.record(key: "v1", position: 120, duration: 600)
    store.clear(key: "v1")
    XCTAssertNil(store.progress(for: "v1"))
  }
}
