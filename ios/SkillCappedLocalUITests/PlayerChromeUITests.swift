import XCTest

/// The player's transport has two shapes and one order. A wide window keeps the
/// whole of it in a single row — skip back, play, skip forward, the timeline, the
/// speed, the queue's neighbours — while a portrait phone floats the three
/// least-used controls above the bar, which is what buys the timeline the width
/// to show both readouts. Picture in Picture is alone in the top-right corner in
/// both shapes. The demo library's lessons are empty files, which is enough: the
/// chrome is drawn as soon as the player exists.
final class PlayerChromeUITests: XCTestCase {
  func testPortraitFloatsTheRateAndTheQueueAboveTheBar() {
    let app = openPlayer()
    showTransport(in: app)

    let bar = [app.buttons["Back 10 seconds"], app.buttons["Forward 10 seconds"], playButton(in: app)]
    let floating = [
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed")).firstMatch,
      app.buttons["Previous lesson"],
      app.buttons["Next lesson"],
    ]

    for control in bar + floating {
      XCTAssertTrue(
        control.waitForExistence(timeout: 5),
        "every control should still be reachable; window \(app.frame), buttons on screen: \(buttonsOnScreen(in: app))"
      )
    }

    guard (bar + floating).allSatisfy({ $0.exists }) else { return }

    let barMiddle = bar.map { $0.frame.midY }
    XCTAssertLessThanOrEqual(
      (barMiddle.max() ?? 0) - (barMiddle.min() ?? 0),
      10,
      "skip back, play and skip forward share the bar"
    )

    let floatingMiddle = floating.map { $0.frame.midY }
    XCTAssertLessThanOrEqual(
      (floatingMiddle.max() ?? 0) - (floatingMiddle.min() ?? 0),
      10,
      "the rate and the two queue steps share one band"
    )
    XCTAssertLessThan(
      floatingMiddle.max() ?? 0,
      (barMiddle.min() ?? 0) - 20,
      "…and that band floats above the bar rather than sitting in it"
    )

    let order = floating.map { $0.frame.midX }
    XCTAssertEqual(order, order.sorted(), "the floating band keeps the row's order: speed, previous, next")

    XCTAssertTrue(app.staticTexts["player.elapsed"].exists, "the elapsed time should be in the bar")
    XCTAssertTrue(app.staticTexts["player.remaining"].exists, "with the time left beside it")

    assertPictureInPictureAtTheTop(in: app, above: floatingMiddle.max() ?? 0)

    let portrait = XCTAttachment(screenshot: app.screenshot())
    portrait.name = "player-transport-portrait"
    portrait.lifetime = .keepAlways
    add(portrait)
  }

  func testLandscapeKeepsTheWholeTransportInOneRow() {
    let app = openPlayer()
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }

    showTransport(in: app)

    let controls = [
      (name: "back", element: app.buttons["Back 10 seconds"]),
      (name: "forward", element: app.buttons["Forward 10 seconds"]),
      (name: "play", element: playButton(in: app)),
      (
        name: "speed",
        element: app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed")).firstMatch
      ),
      (name: "previous", element: app.buttons["Previous lesson"]),
      (name: "next", element: app.buttons["Next lesson"]),
    ]

    for control in controls {
      XCTAssertTrue(
        control.element.waitForExistence(timeout: 5),
        "the \(control.name) control should be in the transport; window \(app.frame), buttons on screen: \(buttonsOnScreen(in: app))"
      )
    }

    guard controls.allSatisfy({ $0.element.exists }) else { return }

    let middle = controls.map { $0.element.frame.midY }
    XCTAssertLessThanOrEqual(
      (middle.max() ?? 0) - (middle.min() ?? 0),
      10,
      "a landscape window has room for the whole transport in one row"
    )

    assertPictureInPictureAtTheTop(in: app, above: middle.min() ?? 0)

    let landscape = XCTAttachment(screenshot: app.screenshot())
    landscape.name = "player-transport-landscape"
    landscape.lifetime = .keepAlways
    add(landscape)
  }

  private func openPlayer() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let course = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(course.waitForExistence(timeout: 40), "the course card should render")
    course.tap()

    let play = app.buttons["Play Why You Suck at ADC (ADC) from the first lesson"]
    XCTAssertTrue(play.waitForExistence(timeout: 15), "the course page should offer Play")
    play.tap()

    XCTAssertTrue(
      app.buttons["Back 10 seconds"].waitForExistence(timeout: 30),
      "the player should open its transport"
    )
    return app
  }

  /// Picture in Picture sits on its own, above everything else and at the right.
  private func assertPictureInPictureAtTheTop(
    in app: XCUIApplication,
    above top: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let pictureInPicture = app.buttons["Picture in picture"]
    guard pictureInPicture.exists else { return }
    XCTAssertLessThan(
      pictureInPicture.frame.midY,
      top - 80,
      "Picture in picture belongs at the top of the screen, not in the transport",
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

  private func playButton(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label IN %@", ["Play", "Pause"])).firstMatch
  }

  /// A single tap on the picture is how a person brings the chrome back once it
  /// has faded: it only goes away while the video is really advancing, so the
  /// tap cannot talk the test out of a transport it never had.
  private func showTransport(in app: XCUIApplication) {
    guard !app.buttons["Back 10 seconds"].exists else { return }
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
    _ = app.buttons["Back 10 seconds"].waitForExistence(timeout: 5)
  }

  /// What the transport really looks like when an assertion fails: the labels
  /// iOS put in the accessibility tree and where each one sits, so a missing
  /// control is named as missing or as sitting off the edge of the window
  /// instead of being guessed at.
  private func buttonsOnScreen(in app: XCUIApplication) -> String {
    app.buttons.allElementsBoundByIndex.map { "\($0.label)@\($0.frame.origin)" }.joined(separator: " | ")
  }
}
