import XCTest

/// A lesson row answers to two gestures, and both have to end somewhere: a left
/// swipe and a long press each offer the same pair — take the file off the phone,
/// or leave the phone with it. A whole course offers them for every video it holds.
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

  func testSweepingALessonLeftOffersToExportOrDeleteIt() {
    let app = openCourse()
    let row = app.staticTexts["Farming Fundamentals"]
    row.swipeLeft()

    let export = app.buttons["Export"]
    XCTAssertTrue(
      export.waitForExistence(timeout: 5),
      "a left swipe should reveal Export — the row's actions are \(app.buttons.allElementsBoundByIndex.map(\.label))"
    )
    XCTAssertTrue(app.buttons["Delete"].exists, "and Delete beside it")

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "lesson-actions-swipe"
    shot.lifetime = .keepAlways
    add(shot)

    // Leave the row at rest, so nothing carries into the next launch's state.
    row.swipeRight()
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

    // Dismiss the menu on the page's own chrome. A coordinate tap never asks the
    // element to scroll itself into view, which AX refuses for a pinned header.
    app.navigationBars.firstMatch
      .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .tap()
  }

  /// A course is a folder of videos, so its long press has to speak for all of
  /// them — the label carries the count, because "Delete" alone would not say how
  /// much is about to go.
  func testHoldingACourseOffersToExportOrDeleteEveryVideoInIt() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let card = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(card.waitForExistence(timeout: 40), "the course card should render")
    card.press(forDuration: 1.2)

    let deleteAll = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Delete all'")
    ).firstMatch
    XCTAssertTrue(
      deleteAll.waitForExistence(timeout: 5),
      "a long press should offer the whole course — on screen: \(app.buttons.allElementsBoundByIndex.map(\.label))"
    )
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Export all'")).firstMatch.exists,
      "and Export all its videos beside it"
    )

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "course-actions-menu"
    shot.lifetime = .keepAlways
    add(shot)

    app.navigationBars.firstMatch
      .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .tap()
  }
}
