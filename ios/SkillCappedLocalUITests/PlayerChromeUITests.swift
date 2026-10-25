import XCTest

/// The player's transport has two shapes and one order. A wide window keeps the
/// whole of it in a single row — skip back, play, skip forward, the timeline, the
/// speed, the queue's neighbours and the queue itself — while a portrait phone
/// floats the four least-used controls above the bar, which is what buys the
/// timeline the width to show both readouts. The fit control and Picture in
/// Picture sit in the top-right corner in both shapes. The demo library's lessons
/// are empty files, which is enough: the chrome is drawn as soon as the player
/// exists.
final class PlayerChromeUITests: XCTestCase {
  func testPortraitFloatsTheRateAndTheQueueAboveTheBar() {
    let app = openPlayer()
    showTransport(in: app)

    let bar = [app.buttons["Back 10 seconds"], app.buttons["Forward 10 seconds"], playButton(in: app)]
    let floating = [
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed")).firstMatch,
      app.buttons["Previous lesson"],
      app.buttons["Next lesson"],
      app.buttons["Queue"],
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
    XCTAssertEqual(order, order.sorted(), "the floating band keeps the row's order: speed, previous, next, queue")

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
    waitForLandscape(app)

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
      (name: "queue", element: app.buttons["Queue"]),
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

    // The corners are used, not avoided: a rounded display asks a control to sit
    // in it. Both corners of the header take one, each far enough off the glass
    // that the continuous curve cannot clip it and close enough to read as
    // sitting *in* the corner rather than beside it. The glass of a phone on its
    // side has already come back about eight points at the diagonal.
    let screen = app.frame
    let close = app.buttons["Close"]
    XCTAssertTrue(close.exists, "the header should carry a close button; window \(screen)")
    if close.exists {
      let left = close.frame.minX - screen.minX
      let top = close.frame.minY - screen.minY
      XCTAssertGreaterThanOrEqual(
        left,
        8,
        "the close button should stay off the corner's glass; close at \(close.frame), window \(screen)"
      )
      XCTAssertGreaterThanOrEqual(top, 8, "…and off the top edge")
      XCTAssertLessThanOrEqual(
        left,
        40,
        "…while sitting in the corner rather than a flat margin away from it (\(left) points in)"
      )
    }

    let pictureInPicture = app.buttons["Picture in picture"]
    if pictureInPicture.exists {
      let right = screen.maxX - pictureInPicture.frame.maxX
      XCTAssertGreaterThanOrEqual(
        right,
        8,
        "Picture in picture should stay off the right corner too; it sits at \(pictureInPicture.frame), window \(screen)"
      )
      XCTAssertLessThanOrEqual(right, 40, "…and sit in that corner (\(right) points in)")
    }

    let leading = app.buttons["Back 10 seconds"].frame.minX - screen.minX
    let trailing = screen.maxX - app.buttons["Queue"].frame.maxX
    XCTAssertEqual(
      leading,
      trailing,
      accuracy: 4,
      "the transport should sit centred in the window: \(leading) points at the left, \(trailing) at the right"
    )

    assertPictureInPictureAtTheTop(in: app, above: middle.min() ?? 0)

    let landscape = XCTAttachment(screenshot: app.screenshot())
    landscape.name = "player-transport-landscape"
    landscape.lifetime = .keepAlways
    add(landscape)
  }

  /// A hold is a speed control, not a tap: pressing the picture must not be
  /// read as the tap that toggles the chrome, or a viewer speeding a lesson up
  /// would hide their own transport.
  func testHoldingThePictureDoesNotToggleTheChrome() {
    let app = openPlayer()
    showTransport(in: app)

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)

    XCTAssertTrue(
      app.buttons["Back 10 seconds"].waitForExistence(timeout: 5),
      "the transport should still be on screen after a hold; buttons on screen: \(buttonsOnScreen(in: app))"
    )
  }

  /// The queue is reachable without leaving the player, and it is a list of
  /// lessons rather than a set of arrows: a row carries the lesson's name, how
  /// long it runs and how much of it is behind the viewer, and choosing one plays
  /// it and puts the drawer away.
  func testTheQueueDrawerListsTheLessonsAndPlaysOne() {
    let app = openPlayer()
    showTransport(in: app)

    let queue = app.buttons["Queue"]
    XCTAssertTrue(
      queue.waitForExistence(timeout: 5),
      "the transport should carry the queue; buttons on screen: \(buttonsOnScreen(in: app))"
    )
    guard queue.exists else { return }
    queue.tap()

    let titles = ["What's Next", "Farming Fundamentals"]
    let playing = titles.first { app.staticTexts[$0].exists } ?? titles[0]
    let other = titles.first { $0 != playing } ?? titles[1]

    XCTAssertTrue(
      app.buttons[other].waitForExistence(timeout: 5),
      "the drawer should list the lesson that is not on screen; buttons on screen: \(buttonsOnScreen(in: app))"
    )

    for title in titles {
      let value = app.buttons[title].value as? String ?? ""
      XCTAssertTrue(
        value.contains(":"),
        "each row should carry how long its lesson runs; \(title) reads \"\(value)\""
      )
    }

    app.buttons[other].tap()

    XCTAssertTrue(
      app.staticTexts[other].waitForExistence(timeout: 20),
      "choosing a lesson should play it; buttons on screen: \(buttonsOnScreen(in: app))"
    )
    XCTAssertFalse(
      app.buttons[playing].exists,
      "…and put the drawer away — the row that was on screen should be gone"
    )
  }

  /// The picture fills the window one of two ways, and the control says which one
  /// it will move to rather than which one is on.
  func testTheFitControlTogglesWhatItSays() {
    let app = openPlayer()
    showTransport(in: app)

    let toFill = app.buttons["Fill the screen"]
    let toFit = app.buttons["Fit the whole video"]
    XCTAssertTrue(
      toFill.waitForExistence(timeout: 5) || toFit.waitForExistence(timeout: 5),
      "the header should offer the fit control; buttons on screen: \(buttonsOnScreen(in: app))"
    )

    if toFill.exists {
      toFill.tap()
      XCTAssertTrue(
        toFit.waitForExistence(timeout: 5),
        "filling the screen should leave the control offering the whole video"
      )
    } else if toFit.exists {
      toFit.tap()
      XCTAssertTrue(
        toFill.waitForExistence(timeout: 5),
        "fitting the whole video should leave the control offering the fill"
      )
    }
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

  /// Rotation is an animation, and the transport is re-laid out during it: reading
  /// y positions mid-turn compares two shapes and calls the result a stack.
  private func waitForLandscape(_ app: XCUIApplication) {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, app.frame.width <= app.frame.height {
      Thread.sleep(forTimeInterval: 0.1)
    }
    Thread.sleep(forTimeInterval: 0.6)
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
