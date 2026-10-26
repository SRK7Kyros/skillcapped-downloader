import Foundation
import XCTest

@testable import SkillCappedLocal

/// The numbers the system's own download card is drawn from, and the identifier
/// the app has to declare for iOS to hand it a task at all.
///
/// Both are arithmetic and both are easy to get quietly wrong: a bar whose total
/// grows when a lesson starts reads as going backwards, and an identifier the
/// plist does not name fails with nothing visible except a queue that behaves like
/// it did before iOS 26 existed.
@MainActor
final class ContinuedProcessingTests: XCTestCase {
  func testALessonNobodyHasPlannedIsSizedFromItsLength() {
    let lesson = task("a", duration: 122)
    XCTAssertEqual(ContinuedRun.plannedParts(for: lesson), 14)
  }

  func testAPublishedPartCountBeatsTheLength() {
    let lesson = task("a", duration: 122, total: 13)
    XCTAssertEqual(ContinuedRun.plannedParts(for: lesson), 13)
  }

  func testALessonWithNoLengthAndNoPartsIsStillOnePartOfWork() {
    XCTAssertEqual(ContinuedRun.plannedParts(for: task("a", duration: 0)), 1)
  }

  func testTheBarMovesOnWhenALessonLandsInsteadOfGoingBack() {
    var run = ContinuedRun()
    run.observe([
      task("a", title: "Wave management", duration: 118, state: .downloading, done: 4, total: 13),
      task("b", title: "Crashing", duration: 122),
    ])
    XCTAssertEqual(run.total, 27)
    XCTAssertEqual(run.completed, 4)

    // The first lesson landed and the second started: its plan was fixed the first
    // time it was seen, so the denominator does not move.
    run.observe([
      task("a", title: "Wave management", state: .ready, done: 13, total: 13),
      task("b", title: "Crashing", duration: 122, state: .downloading, done: 1, total: 14),
    ])
    XCTAssertEqual(run.total, 27)
    XCTAssertEqual(run.completed, 14)
  }

  func testALessonThePersonCancelledLeavesTheTotalWithIt() {
    var run = ContinuedRun()
    run.observe([
      task("a", duration: 118, state: .queued),
      task("b", duration: 122, state: .queued),
      task("c", duration: 122, state: .queued),
    ])
    XCTAssertEqual(run.total, 42)

    run.observe([
      task("a", duration: 118, state: .queued),
      task("c", duration: 122, state: .queued),
    ])
    XCTAssertEqual(run.total, 28)
    XCTAssertEqual(run.lessonsLeft, 2)
  }

  func testAPausedLessonKeepsItsPlaceInThePlan() {
    var run = ContinuedRun()
    run.observe([task("a", duration: 122, state: .paused, done: 3)])
    XCTAssertEqual(run.lessonsLeft, 1)
    XCTAssertEqual(run.completed, 3)
  }

  func testCompletedNeverPassesThePlan() {
    var run = ContinuedRun()
    run.observe([task("a", duration: 122, state: .downloading, done: 40, total: 3)])
    XCTAssertEqual(run.completed, run.total)
  }

  func testALessonAlreadyOnDiskIsNotWorkThisRunHasToDo() {
    var run = ContinuedRun()
    run.observe([task("a", state: .ready, done: 13, total: 13)])
    XCTAssertFalse(run.hasWork)
  }

  func testTheCardNamesTheLessonInFrontAndKeepsTheCourseLast() {
    var run = ContinuedRun()
    run.observe([
      task("a", title: "Wave management", course: "Fundamentals", state: .downloading),
      task("b", title: "Crashing", course: "Fundamentals", state: .queued),
    ])
    XCTAssertEqual(run.title, "Downloading Wave management")
    XCTAssertEqual(run.subtitle, "2 lessons left · Fundamentals")
  }

  func testTheLastLessonSaysSoRatherThanCountingOne() {
    var run = ContinuedRun()
    run.observe([
      task("a", title: "Wave management", state: .downloading, done: 12, total: 13),
      task("b", title: "Crashing", state: .queued),
    ])
    run.observe([
      task("a", title: "Wave management", state: .ready, done: 13, total: 13),
      task("b", title: "Crashing", state: .downloading, done: 1, total: 13),
    ])
    XCTAssertEqual(run.title, "Downloading Crashing")
    XCTAssertEqual(run.subtitle, "Last lesson · A course")
  }

  func testAQueueWithNoCourseNamesTheLessonItIsFetching() {
    var run = ContinuedRun()
    run.observe([task("a", title: "Wave management", course: nil, state: .downloading)])
    XCTAssertEqual(run.title, "Downloading Wave management")
    XCTAssertEqual(run.subtitle, "Last lesson")
  }

  func testAQueueWithNothingKnownAboutItStillSaysWhatTheAppIsDoing() {
    var run = ContinuedRun()
    run.observe([task("a", title: "", course: nil, state: .queued)])
    XCTAssertEqual(run.title, "Downloading lessons")
    XCTAssertEqual(run.subtitle, "Last lesson")
  }

  func testTheEstimateIsSizedByThePartsTheLessonShowsAndTheSpeedItRunsAt() {
    var run = ContinuedRun()
    run.observe(
      [task("a", title: "Wave management", course: "Fundamentals", state: .downloading, done: 4, total: 13, bytes: 8_000_000)],
      bytesPerSecond: 25_000
    )
    XCTAssertEqual(run.bytesPerPart, 2_000_000)
    XCTAssertEqual(run.secondsLeft, 720)
    XCTAssertEqual(run.subtitle, "Last lesson · ~12 min left · Fundamentals")
  }

  func testNoPartLandedMeansNoEstimateRatherThanAGuess() {
    var run = ContinuedRun()
    run.observe(
      [task("a", title: "Wave management", course: "Fundamentals", state: .downloading, total: 13)],
      bytesPerSecond: 1_000_000
    )
    XCTAssertNil(run.secondsLeft)
    XCTAssertEqual(run.subtitle, "Last lesson · Fundamentals")
  }

  func testThePartSizeSurvivesIntoTheNextLesson() {
    var run = ContinuedRun()
    run.observe([
      task("a", title: "Wave management", state: .downloading, done: 4, total: 13, bytes: 8_000_000),
      task("b", title: "Crashing", state: .queued, total: 13),
    ], bytesPerSecond: 1_000_000)
    run.observe([
      task("a", title: "Wave management", state: .ready, done: 13, total: 13),
      task("b", title: "Crashing", state: .downloading, total: 13),
    ], bytesPerSecond: 1_000_000)
    XCTAssertEqual(run.bytesPerPart, 2_000_000)
    XCTAssertNotNil(run.secondsLeft)
  }

  func testTheDurationItPrintsIsRoundedAndMarkedAsAnEstimate() {
    XCTAssertEqual(ContinuedRun.duration(20), "under a minute")
    XCTAssertEqual(ContinuedRun.duration(720), "~12 min")
    XCTAssertEqual(ContinuedRun.duration(3_900), "~1 hr 5 min")
    XCTAssertEqual(ContinuedRun.duration(7_200), "~2 hr")
  }

  func testAQueueThatHasFinishedSaysSoRatherThanCountingDown() {
    var run = ContinuedRun()
    run.observe([task("a", title: "Wave management", course: "Fundamentals", state: .ready, done: 13, total: 13)])
    XCTAssertEqual(run.subtitle, "Nothing left")
  }

  func testTheIdentifierStaysInsideTheAppsOwnNamespace() {
    XCTAssertTrue(ContinuedProcessing.identifier.hasPrefix("com.kyros.skillcappedlocal."))
  }

  /// The scheduler answers a registration for an identifier its plist does not name
  /// with `false`, and this app then keeps using a background assertion — which
  /// looks exactly like everything working, on a device, for ever.
  func testTheIdentifierTheAppRegistersIsOneItsPlistPermits() throws {
    let ios = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(contentsOf: ios.appendingPathComponent("SkillCappedLocal/Info.plist"))
    let root = try PropertyListSerialization.propertyList(from: data, format: nil)
    let plist = try XCTUnwrap(root as? [String: Any])
    let permitted = try XCTUnwrap(plist["BGTaskSchedulerPermittedIdentifiers"] as? [String])
    XCTAssertTrue(permitted.contains(ContinuedProcessing.identifier))
  }

  private func task(
    _ uuid: String,
    title: String = "A lesson",
    course: String? = "A course",
    duration: Int = 122,
    state: DownloadState = .queued,
    done: Int = 0,
    total: Int = 0,
    bytes: Int64 = 0
  ) -> DownloadTask {
    DownloadTask(
      uuid: uuid,
      title: title,
      kind: "course",
      role: "ADC",
      category: "",
      courseTitle: course,
      durationSec: duration,
      quality: "1080p",
      actualQuality: nil,
      state: state,
      segmentsDone: done,
      segmentsTotal: total,
      bytes: bytes,
      error: nil,
      createdAt: Date(timeIntervalSince1970: 0),
      finishedAt: nil,
      path: nil
    )
  }
}
