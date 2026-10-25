import XCTest

/// The one thing the user asked for by hand: a way to hand the background log
/// over without screenshotting a scrolling form. It sits in the sheet's own bar,
/// above the form, so nothing has to be scrolled to reach it — and it has to say
/// what it did, because a copy that looks like nothing happened gets tapped twice.
final class SettingsUITests: XCTestCase {
  func testTheBackgroundLogCanBeCopiedInOneTap() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary", "-demoCatalog"]
    app.launch()

    let settings = app.buttons["Library settings"]
    XCTAssertTrue(
      settings.waitForExistence(timeout: 40),
      "the toolbar should offer settings:\n\(app.debugDescription)"
    )
    settings.tap()

    let copy = app.buttons["settings.copyLogs"]
    XCTAssertTrue(
      copy.waitForExistence(timeout: 20),
      "the sheet should offer the copy above its form:\n\(app.debugDescription)"
    )
    XCTAssertTrue(
      copy.isHittable,
      "the copy should be reachable without scrolling:\n\(app.debugDescription)"
    )
    XCTAssertEqual(copy.label, "Copy logs")

    // The durable proof, polled as a fresh query: reading `label` off the element
    // failed a whole run when one accessibility snapshot landed mid re-render,
    // whereas `exists` answers false. A second tap costs nothing (it copies
    // again) and covers a first tap the system swallowed.
    let confirmation = app.staticTexts["settings.copyLogs.confirmation"]
    var copied = false
    var attempts = 0
    while !copied && attempts < 2 {
      attempts += 1
      guard copy.exists else { break }
      copy.tap()
      var polls = 0
      while !copied && polls < 15 {
        copied = confirmation.exists
        if !copied { Thread.sleep(forTimeInterval: 0.2) }
        polls += 1
      }
    }

    let dump = XCTAttachment(string: app.debugDescription)
    dump.name = "settings-after-copy"
    dump.lifetime = .keepAlways
    add(dump)

    XCTAssertTrue(
      copied,
      "copying should say what reached the clipboard:\n\(app.debugDescription)"
    )

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "settings-copied"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
