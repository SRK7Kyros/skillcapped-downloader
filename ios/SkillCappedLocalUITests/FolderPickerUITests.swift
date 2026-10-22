import XCTest

/// The folder button used to kill the app: UIKit raises an Objective-C exception
/// from the picker's initializer when the running signature carries no iCloud
/// container entitlement. This drives the real button and insists the system
/// folder picker presents — and that it can be dismissed again.
final class FolderPickerUITests: XCTestCase {
  func testTheFolderButtonPresentsTheSystemPicker() {
    let app = XCUIApplication()
    app.launch()

    let welcome = app.buttons["Choose a folder"]
    let toolbar = app.buttons["Library folder"]
    if welcome.waitForExistence(timeout: 40) {
      welcome.tap()
    } else {
      XCTAssertTrue(toolbar.waitForExistence(timeout: 10), "either the welcome button or the toolbar folder button is on screen")
      toolbar.tap()
    }

    let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Choose a folder'")).firstMatch
    XCTAssertTrue(choose.waitForExistence(timeout: 15), "the library sheet should open")
    choose.tap()

    let open = app.buttons["Open"]
    let cancel = app.buttons["Cancel"]
    let browse = app.buttons["Browse"]
    let pickerIsUp = { open.exists || cancel.exists || browse.exists }
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline, !pickerIsUp() {
      Thread.sleep(forTimeInterval: 0.3)
    }

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "picker"
    shot.lifetime = .keepAlways
    add(shot)

    XCTAssertTrue(pickerIsUp(), "the system folder picker should present:\n\(app.debugDescription)")
    XCTAssertEqual(app.state, .runningForeground, "the picker must not kill the app")

    if cancel.exists {
      cancel.tap()
    } else {
      let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
      let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
      top.press(forDuration: 0.1, thenDragTo: bottom)
    }
    XCTAssertTrue(choose.waitForExistence(timeout: 20), "the picker dismisses back to the sheet:\n\(app.debugDescription)")
  }
}
