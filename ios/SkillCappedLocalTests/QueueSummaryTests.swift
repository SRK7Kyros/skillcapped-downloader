import XCTest

@testable import SkillCappedLocal

final class QueueSummaryTests: XCTestCase {
  private func task(
    _ uuid: String,
    state: DownloadState,
    done: Int = 0,
    total: Int = 0,
    bytes: Int64 = 0,
    title: String = "Lesson",
    course: String? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 0)
  ) -> DownloadTask {
    DownloadTask(
      uuid: uuid,
      title: title,
      kind: "course",
      role: "adc",
      category: "",
      courseTitle: course,
      durationSec: 60,
      quality: nil,
      actualQuality: nil,
      state: state,
      segmentsDone: done,
      segmentsTotal: total,
      bytes: bytes,
      error: nil,
      createdAt: createdAt,
      finishedAt: nil,
      path: nil
    )
  }

  func testNothingLeftInTheQueueMeansNoActivity() {
    XCTAssertNil(QueueSummary.of([]))
    XCTAssertNil(QueueSummary.of([
      task("a", state: .ready, done: 12, total: 12),
      task("b", state: .failed),
    ]))
  }

  func testOneLessonInFlightCarriesItsOwnParts() {
    let summary = QueueSummary.of([task("a", state: .downloading, done: 30, total: 120, bytes: 900, title: "Farming")])

    XCTAssertEqual(summary?.lessonsLeft, 1)
    XCTAssertEqual(summary?.segmentsDone, 30)
    XCTAssertEqual(summary?.segmentsTotal, 120)
    XCTAssertEqual(summary?.bytesDone, 900)
    XCTAssertEqual(summary?.currentTitle, "Farming")
    XCTAssertEqual(summary?.percent ?? 0, 0.25, accuracy: 0.0001)
    XCTAssertEqual(summary?.paused, false)
  }

  func testTheQueueAddsUpEveryPartOfEveryLesson() {
    let summary = QueueSummary.of([
      task("a", state: .downloading, done: 10, total: 20, bytes: 100),
      task("b", state: .queued, done: 0, total: 40, bytes: 0),
      task("c", state: .ready, done: 60, total: 60, bytes: 500),
    ])

    XCTAssertEqual(summary?.lessonsLeft, 2)
    XCTAssertEqual(summary?.segmentsDone, 10)
    XCTAssertEqual(summary?.segmentsTotal, 60)
    XCTAssertEqual(summary?.percent ?? 0, 1.0 / 6.0, accuracy: 0.0001)
  }

  func testTheLessonInFrontIsTheOneDownloadingWhateverItsPlaceInTheQueue() {
    let queuedFirst = task("a", state: .queued, title: "Waiting", createdAt: Date(timeIntervalSince1970: 0))
    let running = task("b", state: .downloading, done: 1, total: 4, title: "Running", createdAt: Date(timeIntervalSince1970: 10))
    let summary = QueueSummary.of([running, queuedFirst])

    XCTAssertEqual(summary?.currentTitle, "Running")
  }

  func testAQueuedLessonIsNotReportedAsPaused() {
    XCTAssertEqual(QueueSummary.of([task("a", state: .queued)])?.paused, false)
    XCTAssertEqual(QueueSummary.of([task("a", state: .downloading, done: 1, total: 2)])?.paused, false)
  }

  func testEverythingPausedReadsAsPaused() {
    let summary = QueueSummary.of([
      task("a", state: .paused, done: 3, total: 10),
      task("b", state: .paused),
    ])

    XCTAssertEqual(summary?.paused, true)
    XCTAssertEqual(summary?.lessonsLeft, 2)
  }

  func testTheCourseTitleTravelsWithTheLesson() {
    let summary = QueueSummary.of([
      task("a", state: .downloading, done: 1, total: 2, course: "Why You Suck at ADC"),
    ])

    XCTAssertEqual(summary?.currentCourse, "Why You Suck at ADC")
  }

  func testPercentIsZeroWithoutAPartCountAndNeverBeyondOne() {
    XCTAssertEqual(QueueSummary.of([task("a", state: .downloading)])?.percent, 0)

    let overrun = QueueSummary.of([task("a", state: .downloading, done: 20, total: 10)])
    XCTAssertEqual(overrun?.percent, 1)
  }

  func testTheStateCarriesTheSameNumbersToTheActivity() {
    let summary = QueueSummary.of([
      task("a", state: .downloading, done: 5, total: 20, bytes: 640, title: "Wave clear", course: "Macro")
    ])
    let state = summary?.state

    XCTAssertEqual(state?.lessonsLeft, 1)
    XCTAssertEqual(state?.segmentsDone, 5)
    XCTAssertEqual(state?.segmentsTotal, 20)
    XCTAssertEqual(state?.bytesDone, 640)
    XCTAssertEqual(state?.currentTitle, "Wave clear")
    XCTAssertEqual(state?.currentCourse, "Macro")
    XCTAssertEqual(state?.percent ?? 0, 0.25, accuracy: 0.0001)
  }
}
