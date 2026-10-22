import XCTest

/// The folder button used to kill the app: UIKit raises an Objective-C exception
/// from the picker's initializer when the running signature carries no iCloud
/// container entitlement. This drives the real button and insists the system
/// picker appears.
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

    let cancel = app.buttons["Cancel"]
    let presented = cancel.waitForExistence(timeout: 30)

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "picker"
    shot.lifetime = .keepAlways
    add(shot)

    XCTAssertTrue(presented, "the system folder picker should present:\n\(app.debugDescription)")
    XCTAssertEqual(app.state, .runningForeground, "the picker must not kill the app")

    cancel.tap()
    XCTAssertTrue(choose.waitForExistence(timeout: 20), "dismissing the picker returns to the sheet")
  }
}
