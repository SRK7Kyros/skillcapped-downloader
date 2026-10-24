import XCTest

/// The folder button used to kill the app: UIKit raises an Objective-C exception
/// from the picker's initializer (a folder-only type array is refused on iOS 26+,
/// whatever `asCopy` says). These drive the real button and insist the system
/// folder picker presents — and that both ways out of it work.
///
/// The toolbar's folder button is used rather than the welcome screen's, because
/// the library tab can open on the welcome copy, on a read of the folder, or on
/// a library the container already holds — the toolbar is there in all three.
final class FolderPickerUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  func testTheFolderButtonPresentsTheSystemPicker() {
    let app = XCUIApplication()
    app.launch()

    let choose = openSheet(in: app)
    choose.tap()

    let picker = waitForPicker(in: app)

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "picker"
    shot.lifetime = .keepAlways
    add(shot)

    XCTAssertNotNil(picker, "the system folder picker should present:\n\(app.debugDescription)")
    XCTAssertEqual(app.state, .runningForeground, "the picker must not kill the app")

    if app.buttons["Cancel"].exists {
      app.buttons["Cancel"].tap()
    } else {
      let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
      let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
      top.press(forDuration: 0.1, thenDragTo: bottom)
    }
    XCTAssertTrue(choose.waitForExistence(timeout: 20), "the picker dismisses back to the sheet:\n\(app.debugDescription)")
  }

  /// **Open** — the button that spins forever when the app forgets it owns the
  /// dismissal. The picker has to leave by itself, and a good pick has to close
  /// the sheet and leave a library behind.
  func testTappingOpenHandsTheFolderBackAndLeavesNoPickerBehind() {
    let app = XCUIApplication()
    app.launch()

    let choose = openSheet(in: app)
    choose.tap()

    XCTAssertNotNil(waitForPicker(in: app), "the picker should present:\n\(app.debugDescription)")
    let open = app.buttons["Open"]
    XCTAssertTrue(open.waitForExistence(timeout: 30), "the picker should offer Open:\n\(app.debugDescription)")
    XCTAssertEqual(
      XCTWaiter().wait(
        for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: open)],
        timeout: 30
      ),
      .completed,
      "Open should become tappable once the picker has read the folder:\n\(app.debugDescription)"
    )
    open.tap()

    if !waitForDismissal(of: open, timeout: 30) {
      // A tap the picker was not ready for is dropped silently, and a person
      // looking at a picker that did not move presses the button again.
      open.tap()
      XCTAssertTrue(
        waitForDismissal(of: open, timeout: 30),
        "the picker must dismiss on Open instead of spinning:\n\(app.debugDescription)"
      )
    }

    XCTAssertEqual(app.state, .runningForeground, "the pick must not kill the app")
    XCTAssertTrue(
      app.buttons["Library folder"].waitForExistence(timeout: 30),
      "the library should come back once the pick is applied:\n\(app.debugDescription)"
    )

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "after-open"
    shot.lifetime = .keepAlways
    add(shot)
  }

  private func waitForDismissal(of element: XCUIElement, timeout: TimeInterval) -> Bool {
    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  private func openSheet(in app: XCUIApplication) -> XCUIElement {
    let folder = app.buttons["Library folder"]
    XCTAssertTrue(folder.waitForExistence(timeout: 60), "the library tab should be up:\n\(app.debugDescription)")
    folder.tap()

    let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Choose a folder'")).firstMatch
    XCTAssertTrue(choose.waitForExistence(timeout: 30), "the library sheet should open:\n\(app.debugDescription)")
    return choose
  }

  private func waitForPicker(in app: XCUIApplication) -> XCUIElement? {
    let names = ["Open", "Cancel", "Browse", "Select"]
    let deadline = Date().addingTimeInterval(40)
    while Date() < deadline {
      for name in names where app.buttons[name].exists {
        return app.buttons[name]
      }
      Thread.sleep(forTimeInterval: 0.3)
    }
    return nil
  }
}
