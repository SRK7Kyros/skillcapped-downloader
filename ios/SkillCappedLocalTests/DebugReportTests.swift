import XCTest

@testable import SkillCappedLocal

/// The block the copy button puts on the clipboard. Its whole job is to be
/// complete and readable on someone else's screen, so the cases are what a reader
/// has to find in it: which build, which folder, what the queue is doing, why the
/// card is or is not there, and every line the journal kept — not the sixteen the
/// form has room for.
final class DebugReportTests: XCTestCase {
  private func activity(
    cards: [String] = ["active"],
    error: String? = nil
  ) -> LiveActivityReport {
    LiveActivityReport(
      enabled: true,
      cards: cards,
      extensionPresent: true,
      extensionSigned: true,
      extensionIdentifier: "com.kyros.skillcappedlocal.widget",
      extensionVersion: "1.24.2 (109)",
      appIdentifier: "com.kyros.skillcappedlocal",
      systemVersion: "27.0",
      error: error
    )
  }

  private func report(
    journal: [String] = [
      "10:31:02 wake: library resolved",
      "10:31:03 lesson started"
    ],
    activity: LiveActivityReport? = nil,
    limit: Int = BackgroundJournal.limit
  ) -> DebugReport {
    DebugReport(
      app: "1.24.2 (109)",
      folder: "On My iPhone › SkillCapped Local",
      source: "On this device",
      queued: 1,
      onDisk: "1.2 GB",
      activity: activity ?? self.activity(),
      journal: journal,
      limit: limit
    )
  }

  func testTheFirstLinesNameTheBuildAndWhereTheLibraryIs() {
    let lines = report().text.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines[0], "SkillCapped Local 1.24.2 (109)")
    XCTAssertEqual(lines[1], "Folder: On My iPhone › SkillCapped Local — On this device")
    XCTAssertEqual(lines[2], "Queue: 1 in the queue · 1.2 GB on disk")
  }

  func testTheLiveActivityVerdictIsInTheBlockWithItsFacts() {
    let text = report().text
    XCTAssertTrue(text.contains("Live Activity: One card is live"))
    XCTAssertTrue(text.contains("Cards allowed: yes"))
    XCTAssertTrue(text.contains("Widget version: 1.24.2 (109)"))
  }

  func testARefusalIsQuotedRatherThanSummarised() {
    let text = report(activity: activity(cards: [], error: "no entitlement")).text
    XCTAssertTrue(text.contains("iOS refused the card: no entitlement"))
  }

  func testEveryJournalLineIsKeptInOrder() {
    let journal = (0..<40).map { String(format: "10:%02d:00 event %d", $0, $0) }
    let text = report(journal: journal).text
    let kept = journal.filter { text.contains($0) }
    XCTAssertEqual(kept, journal, "the block must carry the lines the form cannot show")
  }

  func testAFullJournalSaysOlderLinesWereDropped() {
    let journal = (0..<BackgroundJournal.limit).map { "line \($0)" }
    XCTAssertEqual(
      report(journal: journal).journalHeading,
      "Background queue (last \(BackgroundJournal.limit) lines, older ones dropped)"
    )
  }

  func testAShortJournalCountsItsLines() {
    XCTAssertEqual(report().journalHeading, "Background queue (2 lines)")
    XCTAssertEqual(report(journal: ["10:31:02 wake"]).journalHeading, "Background queue (1 line)")
  }

  func testAnEmptyJournalSaysSoInsteadOfGoingBlank() {
    let block = report(journal: [])
    XCTAssertEqual(block.journalHeading, "Background queue (nothing recorded)")
    XCTAssertTrue(block.text.hasSuffix("(none)"))
  }

  func testTheBlockIsOneStringWithNoTrailingNewline() {
    let text = report().text
    XCTAssertFalse(text.hasSuffix("\n"))
    XCTAssertTrue(text.contains("\n10:31:02 wake: library resolved\n10:31:03 lesson started"))
  }
}
