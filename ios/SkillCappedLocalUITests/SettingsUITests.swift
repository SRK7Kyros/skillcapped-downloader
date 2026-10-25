import XCTest

/// The one thing the user asked for by hand: a way to hand the background log
/// over without screenshotting a scrolling form. The button has to be reachable
/// from the library screen and it has to say what it did — a copy that looks like
/// nothing happened is a button that gets tapped twice.
final class SettingsUITests: XCTestCase {
  func testTheBackgroundLogCanBeCopiedInOneTap() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let settings = app.buttons["Library settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 40), "the toolbar should offer settings")
    settings.tap()

    let copy = app.buttons["settings.copyLogs"]
    XCTAssertTrue(copy.waitForExistence(timeout: 10), "Settings should carry the copy button")
    XCTAssertEqual(copy.label, "Copy logs")

    var swipes = 0
    while !copy.isHittable && swipes < 6 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(copy.isHittable, "the copy button should be reachable by scrolling:\n\(app.debugDescription)")

    copy.tap()

    let says = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", "Copied"),
      object: copy
    )
    XCTAssertEqual(
      XCTWaiter().wait(for: [says], timeout: 5),
      .completed,
      "the button should say what it did — it says \(copy.label)"
    )

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "settings-copied"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
