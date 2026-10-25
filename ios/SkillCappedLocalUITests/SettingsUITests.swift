import XCTest

/// The one thing the user asked for by hand: a way to hand the background log
/// over without screenshotting a scrolling form. The button has to be reachable
/// from the library screen and it has to say what it did — a copy that looks like
/// nothing happened is a button that gets tapped twice.
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

    // A Form builds its rows lazily, and its controls are not always exposed as
    // `buttons` on a newer iOS — so the row is found by identifier whatever type
    // it reports and is scrolled into being before it is tapped.
    let copy = app.descendants(matching: .any)
      .matching(identifier: "settings.copyLogs")
      .firstMatch
    var swipes = 0
    while !(copy.exists && copy.isHittable) && swipes < 8 {
      app.swipeUp()
      swipes += 1
    }

    let tree = app.debugDescription
    let dump = XCTAttachment(string: tree)
    dump.name = "settings-hierarchy"
    dump.lifetime = .keepAlways
    add(dump)

    XCTAssertTrue(copy.exists, "Settings should carry the copy button:\n\(tree)")
    XCTAssertEqual(copy.label, "Copy logs")

    // A scroll view can still be decelerating when XCUITest measures a row, and a
    // tap delivered into that motion is swallowed — so the form is given a moment
    // to settle, and the tap goes through the button itself.
    Thread.sleep(forTimeInterval: 0.5)
    let button = app.buttons["settings.copyLogs"]
    XCTAssertTrue(
      button.isHittable,
      "the copy button should be reachable:\n\(app.debugDescription)"
    )

    // The durable proof, polled as a fresh query: reading `label` off the element
    // failed a whole run when one accessibility snapshot landed mid re-render,
    // whereas `exists` answers false. A second tap costs nothing (it copies
    // again) and covers a first tap the scroll view ate.
    let confirmation = app.staticTexts["settings.copyLogs.confirmation"]
    var copied = false
    var attempts = 0
    while !copied && attempts < 2 {
      attempts += 1
      button.tap()
      var polls = 0
      while !copied && polls < 15 {
        copied = confirmation.exists
        if !copied { Thread.sleep(forTimeInterval: 0.2) }
        polls += 1
      }
    }
    XCTAssertTrue(
      copied,
      "copying should leave a line saying what reached the clipboard:\n\(app.debugDescription)"
    )

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "settings-copied"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
