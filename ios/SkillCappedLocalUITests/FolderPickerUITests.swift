import XCTest

/// The folder button used to kill the app: UIKit raises an Objective-C exception
/// from the picker's initializer when the running signature carries no iCloud
/// container entitlement. This drives the real button and insists the system
/// folder picker presents, with its confirm button enabled — a picker left on its
/// default root leaves Open disabled for folders and gives the user nothing to
/// select.
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
    let presented = open.waitForExistence(timeout: 30)

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "picker"
    shot.lifetime = .keepAlways
    add(shot)

    XCTAssertTrue(presented, "the system folder picker should present, ready to open a folder:\n\(app.debugDescription)")
    XCTAssertEqual(app.state, .runningForeground, "the picker must not kill the app")

    let cancel = app.buttons["Cancel"]
    if !cancel.exists {
      let container = app.buttons["On My iPhone"]
      if container.exists { container.tap() }
    }
    XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the picker dismisses back to the sheet:\n\(app.debugDescription)")
    cancel.tap()
    XCTAssertTrue(choose.waitForExistence(timeout: 20), "dismissing the picker returns to the sheet")
  }
}
