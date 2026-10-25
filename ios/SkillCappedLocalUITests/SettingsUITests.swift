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

    copy.tap()

    // The confirmation is looked for as a fresh query, polled: reading `label`
    // off the element failed the whole test when one accessibility snapshot
    // landed while the row was re-rendering, whereas `exists` answers false.
    // The label reverts after two seconds, so the poll has to be quick.
    let copiedLabel = app.buttons["Copied"]
    var said = false
    var polls = 0
    while !said && polls < 20 {
      said = copiedLabel.exists
      if !said { Thread.sleep(forTimeInterval: 0.2) }
      polls += 1
    }
    XCTAssertTrue(
      said,
      "the button should say what it did for a moment:\n\(app.debugDescription)"
    )

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "settings-copied"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
