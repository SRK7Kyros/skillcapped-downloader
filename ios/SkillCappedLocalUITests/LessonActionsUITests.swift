import XCTest

/// A lesson row answers to two gestures, and both have to end somewhere: a right
/// swipe and a long press each offer the same pair — take the file off the phone,
/// or leave the phone with it.
///
/// Neither test accepts either action: the demo library is what the rest of the
/// suite browses, and a deleted lesson would still be gone three tests later.
final class LessonActionsUITests: XCTestCase {
  private func openCourse() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let course = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(course.waitForExistence(timeout: 40), "the course card should render")
    course.tap()

    XCTAssertTrue(
      app.staticTexts["Farming Fundamentals"].waitForExistence(timeout: 15),
      "the lesson row should be listed"
    )
    return app
  }

  func testSweepingALessonRightOffersToExportOrDeleteIt() {
    let app = openCourse()
    let row = app.staticTexts["Farming Fundamentals"]
    row.swipeRight()

    let export = app.buttons["Export"]
    XCTAssertTrue(
      export.waitForExistence(timeout: 5),
      "a right swipe should reveal Export — the row's actions are \(app.buttons.allElementsBoundByIndex.map(\.label))"
    )
    XCTAssertTrue(app.buttons["Delete"].exists, "and Delete beside it")

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "lesson-actions-swipe"
    shot.lifetime = .keepAlways
    add(shot)

    // Leave the row at rest, so nothing carries into the next launch's state.
    row.swipeLeft()
  }

  func testHoldingALessonOffersTheSameTwoActions() {
    let app = openCourse()
    let row = app.staticTexts["Farming Fundamentals"]
    row.press(forDuration: 1.2)

    XCTAssertTrue(
      app.buttons["Export"].waitForExistence(timeout: 5),
      "a long press should offer Export too — on screen: \(app.buttons.allElementsBoundByIndex.map(\.label))"
    )
    XCTAssertTrue(app.buttons["Delete"].exists, "and Delete beside it")

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "lesson-actions-menu"
    shot.lifetime = .keepAlways
    add(shot)

    // Dismiss the menu by tapping the page's own title: it is chrome, not an action.
    app.navigationBars.staticTexts["Why You Suck at ADC (ADC)"].tap()
  }
}
