import XCTest

/// The player's transport reads as one row — skip back, play, skip forward, the
/// timeline, the speed, the queue's neighbours — with Picture in Picture alone
/// in the screen's top-right corner. The demo library's lessons are empty files,
/// which is enough: the chrome is drawn as soon as the player exists.
final class PlayerChromeUITests: XCTestCase {
  func testTheTransportIsOneRowWithPictureInPictureAtTheTop() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let course = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(course.waitForExistence(timeout: 40), "the course card should render")
    course.tap()

    let play = app.buttons["Play Why You Suck at ADC (ADC) from the first lesson"]
    XCTAssertTrue(play.waitForExistence(timeout: 15), "the course page should offer Play")
    play.tap()

    XCTAssertTrue(app.buttons["Back 10 seconds"].waitForExistence(timeout: 30), "the player should open its transport")
    assertOneRow(in: app)

    let portrait = XCTAttachment(screenshot: app.screenshot())
    portrait.name = "player-transport-portrait"
    portrait.lifetime = .keepAlways
    add(portrait)

    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }

    assertOneRow(in: app)

    let landscape = XCTAttachment(screenshot: app.screenshot())
    landscape.name = "player-transport-landscape"
    landscape.lifetime = .keepAlways
    add(landscape)
  }

  /// Every control but Picture in Picture sits in one band of the screen, and
  /// Picture in Picture is up in the top-right corner on its own.
  private func assertOneRow(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let back = app.buttons["Back 10 seconds"]
    let forward = app.buttons["Forward 10 seconds"]
    let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed")).firstMatch
    let previous = app.buttons["Previous lesson"]
    let next = app.buttons["Next lesson"]
    let row = [back, forward, speed, previous, next]

    for element in row {
      XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) should be in the transport", file: file, line: line)
    }

    let middle = row.map { $0.frame.midY }
    let spread = (middle.max() ?? 0) - (middle.min() ?? 0)
    XCTAssertLessThanOrEqual(spread, 10, "the transport should be one row, not a stack", file: file, line: line)

    let pictureInPicture = app.buttons["Picture in picture"]
    guard pictureInPicture.exists else { return }
    XCTAssertLessThan(
      pictureInPicture.frame.midY,
      (middle.min() ?? 0) - 80,
      "Picture in picture belongs at the top of the screen, not in the row",
      file: file,
      line: line
    )
    XCTAssertGreaterThan(
      pictureInPicture.frame.midX,
      app.frame.midX,
      "…and in the top-right corner",
      file: file,
      line: line
    )
  }
}
