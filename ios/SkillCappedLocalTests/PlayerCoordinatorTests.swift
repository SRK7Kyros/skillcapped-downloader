import XCTest
@testable import SkillCappedLocal

@MainActor
final class PlayerCoordinatorTests: XCTestCase {
  private func lesson(_ id: String) -> Lesson {
    Lesson(
      id: id,
      url: URL(fileURLWithPath: "/tmp/\(id).mp4"),
      title: "Lesson \(id)",
      role: "top",
      quality: "1080p",
      seconds: 600,
      bytes: 1_024,
      modified: nil,
      itemId: id,
      needsDownload: false
    )
  }

  private var playlist: [Lesson] { ["a", "b", "c"].map(lesson) }

  func testPlayingAPlaylistCanStepBothWays() {
    let coordinator = PlayerCoordinator()
    let queue = playlist
    coordinator.play(queue[1], in: queue)

    XCTAssertEqual(coordinator.neighbour(of: queue[1], forward: true)?.id, "c")
    XCTAssertEqual(coordinator.neighbour(of: queue[1], forward: false)?.id, "a")
  }

  func testTheEdgesOfTheQueueDoNotWrap() {
    let coordinator = PlayerCoordinator()
    let queue = playlist
    coordinator.play(queue[0], in: queue)

    XCTAssertNil(coordinator.neighbour(of: queue[0], forward: false))
    coordinator.play(queue[2], in: queue)
    XCTAssertNil(coordinator.neighbour(of: queue[2], forward: true))
  }

  func testALessonOutsideTheQueueBecomesAQueueOfOne() {
    let coordinator = PlayerCoordinator()
    coordinator.play(lesson("z"), in: playlist)

    XCTAssertEqual(coordinator.queue.map(\.id), ["z"])
    XCTAssertNil(coordinator.neighbour(of: lesson("z"), forward: true))
  }

  func testPlayingWithoutAQueueLeavesNowhereToStep() {
    let coordinator = PlayerCoordinator()
    coordinator.play(lesson("a"))

    XCTAssertEqual(coordinator.queue.count, 1)
    XCTAssertNil(coordinator.neighbour(of: lesson("a"), forward: true))
  }

  func testStopClearsTheQueueAsWellAsTheLesson() {
    let coordinator = PlayerCoordinator()
    coordinator.play(lesson("a"), in: playlist)
    coordinator.stop()

    XCTAssertNil(coordinator.lesson)
    XCTAssertTrue(coordinator.queue.isEmpty)
  }
}
