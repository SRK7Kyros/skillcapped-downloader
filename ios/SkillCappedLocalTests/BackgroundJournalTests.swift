import XCTest

@testable import SkillCappedLocal

/// The one record of what the queue did while the screen was off. Its rules are
/// small on purpose: newest last, never more than the cap, and a second instance
/// reads what the first wrote — the delegate thread and the queue are two readers
/// of one file.
final class BackgroundJournalTests: XCTestCase {
  private var url: URL!

  override func setUp() {
    super.setUp()
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("journal-\(UUID().uuidString).txt")
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: url)
    super.tearDown()
  }

  private func event(_ line: String) -> String {
    let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
    return parts.count == 2 ? parts[1] : ""
  }

  func testTheNewestLineIsLast() {
    let journal = BackgroundJournal(url: url)
    journal.record("lesson one")
    journal.record("lesson two")
    XCTAssertEqual(journal.lines(2).map(event), ["lesson one", "lesson two"])
  }

  func testALineCarriesTheTimeItHappened() {
    let line = BackgroundJournal.line(at: Date(), event: "launch")
    XCTAssertEqual(line.split(separator: " ").first?.count, 8)
    XCTAssertEqual(event(line), "launch")
  }

  func testTheJournalKeepsOnlyTheLatestLines() {
    let journal = BackgroundJournal(url: url)
    let total = BackgroundJournal.limit + 10
    for index in 0..<total {
      journal.record("event \(index)")
    }
    let lines = journal.lines(1_000)
    XCTAssertEqual(lines.count, BackgroundJournal.limit)
    XCTAssertEqual(lines.first.map(event), "event 10")
    XCTAssertEqual(lines.last.map(event), "event \(total - 1)")
  }

  func testAnEmptyJournalAnswersNothing() {
    XCTAssertTrue(BackgroundJournal(url: url).lines().isEmpty)
  }

  func testClearForgetsEverything() {
    let journal = BackgroundJournal(url: url)
    journal.record("a")
    journal.record("b")
    journal.clear()
    XCTAssertTrue(journal.lines().isEmpty)
    XCTAssertTrue(BackgroundJournal(url: url).lines().isEmpty)
  }

  func testALaterInstanceSeesWhatAnEarlierOneWrote() {
    BackgroundJournal(url: url).record("from the delegate thread")
    XCTAssertEqual(BackgroundJournal(url: url).lines(1).map(event), ["from the delegate thread"])
  }
}
