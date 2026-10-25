import XCTest

@testable import SkillCappedLocal

/// The chain a lock-screen card has to pass, decided from facts the device can
/// report. Every case here is one the app cannot see by itself: a widget iOS
/// refused to load draws nothing and says nothing.
final class LiveActivityDiagnosticsTests: XCTestCase {
  private func verdict(
    enabled: Bool = true,
    present: Bool = true,
    signed: Bool = true,
    widget: String? = "com.kyros.skillcappedlocal.widget",
    app: String? = "com.kyros.skillcappedlocal",
    cards: [String] = [],
    error: String? = nil
  ) -> LiveActivityVerdict {
    .of(
      enabled: enabled,
      extensionPresent: present,
      extensionSigned: signed,
      extensionIdentifier: widget,
      appIdentifier: app,
      cards: cards,
      error: error
    )
  }

  func testCardsTurnedOffOutranksEverythingElse() {
    XCTAssertEqual(
      verdict(enabled: false, cards: ["active"], error: "something"),
      .cardsOff
    )
  }

  func testAMissingWidgetIsNamedBeforeSignatureAndId() {
    XCTAssertEqual(verdict(present: false, signed: false, widget: nil), .noExtension)
  }

  func testAWidgetWithoutItsSealIsNamed() {
    XCTAssertEqual(verdict(signed: false), .unsignedExtension)
  }

  func testAWidgetThatIsNotThisAppsIsNamed() {
    XCTAssertEqual(
      verdict(widget: "com.someone.else.widget"),
      .foreignExtension("com.someone.else.widget")
    )
  }

  func testARefusalIsQuotedAsItCame() {
    let why = "The download card could not start: The operation couldn’t be completed."
    XCTAssertEqual(verdict(error: why), .refused(why))
  }

  func testAnIdleQueueIsNotAFailure() {
    XCTAssertEqual(verdict(), .idle)
  }

  func testALiveCardIsCounted() {
    XCTAssertEqual(verdict(cards: ["active"]), .showing(1))
    XCTAssertEqual(verdict(cards: ["active", "stale"]), .showing(2))
  }

  func testTheUnsignedSentenceNamesTheSideloader() {
    XCTAssertTrue(
      LiveActivityVerdict.unsignedExtension.sentence.contains("sideloader"),
      LiveActivityVerdict.unsignedExtension.sentence
    )
  }

  func testTheCardSentencePointsAtTheLockScreen() {
    XCTAssertTrue(LiveActivityVerdict.showing(1).sentence.contains("lock screen"))
    XCTAssertTrue(LiveActivityVerdict.showing(2).sentence.contains("2 cards"))
  }

  func testTheFactsNameEveryLinkInTheChain() {
    let report = LiveActivityReport(
      enabled: true,
      cards: [],
      extensionPresent: true,
      extensionSigned: true,
      extensionIdentifier: "com.kyros.skillcappedlocal.widget",
      appIdentifier: "com.kyros.skillcappedlocal",
      systemVersion: "27.0",
      error: nil
    )
    XCTAssertEqual(report.facts.count, 7)
    XCTAssertTrue(report.facts.contains("Cards allowed: yes"))
    XCTAssertTrue(report.facts.contains("Cards live: none"))
    XCTAssertTrue(report.facts.contains("Widget: installed, signed"))
    XCTAssertTrue(report.facts.contains("Widget id: com.kyros.skillcappedlocal.widget"))
    XCTAssertTrue(report.facts.contains("System: iOS 27.0"))
    XCTAssertTrue(report.facts.contains("Last refusal: none"))
    XCTAssertEqual(report.verdict, .idle)
  }

  func testASealIsWhatMakesAWidgetLoadable() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("seal-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertFalse(LiveActivityInspector.isSigned(root))

    let seal = root.appendingPathComponent("_CodeSignature")
    try FileManager.default.createDirectory(at: seal, withIntermediateDirectories: true)
    try Data("sealed".utf8).write(to: seal.appendingPathComponent("CodeResources"))

    XCTAssertTrue(LiveActivityInspector.isSigned(root))
  }
}
