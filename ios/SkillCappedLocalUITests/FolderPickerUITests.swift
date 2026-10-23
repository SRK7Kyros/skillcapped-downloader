import XCTest

/// The folder button used to kill the app: UIKit raises an Objective-C exception
/// from the picker's initializer (a folder-only type array is refused on iOS 26+,
/// whatever `asCopy` says). This drives the real button and insists the system
/// folder picker presents — and that it can be dismissed again.
///
/// The toolbar's folder button is used rather than the welcome screen's, because
/// the library tab can open on the welcome copy, on a read of the folder, or on a
/// library the container already holds — the toolbar is there in all three.
final class FolderPickerUITests: XCTestCase {
  func testTheFolderButtonPresentsTheSystemPicker() {
    let app = XCUIApplication()
    app.launch()

    let folder = app.buttons["Library folder"]
    XCTAssertTrue(folder.waitForExistence(timeout: 60), "the library tab should be up:\n\(app.debugDescription)")
    folder.tap()

    let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Choose a folder'")).firstMatch
    XCTAssertTrue(choose.waitForExistence(timeout: 30), "the library sheet should open:\n\(app.debugDescription)")
    choose.tap()

    let open = app.buttons["Open"]
    let cancel = app.buttons["Cancel"]
    let browse = app.buttons["Browse"]
    let select = app.buttons["Select"]
    let pickerIsUp = { open.exists || cancel.exists || browse.exists || select.exists }
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
