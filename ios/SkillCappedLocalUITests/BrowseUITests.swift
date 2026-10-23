import XCTest

final class BrowseUITests: XCTestCase {
  func testDemoLibraryBrowsesIntoACourse() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let course = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(course.waitForExistence(timeout: 40), "the course card should render")

    let coursesHeader = app.staticTexts["Courses"]
    XCTAssertTrue(coursesHeader.exists, "the courses section should be on screen")

    course.tap()

    XCTAssertTrue(app.staticTexts["Farming Fundamentals"].waitForExistence(timeout: 15), "the lesson row should be listed")

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "course"
    shot.lifetime = .keepAlways
    add(shot)
  }

  func testACoursePageSurvivesLandscape() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let course = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(course.waitForExistence(timeout: 40), "the course card should render")
    course.tap()
    XCTAssertTrue(app.staticTexts["Farming Fundamentals"].waitForExistence(timeout: 15), "the lesson row should be listed")

    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }

    let play = app.buttons["Play Why You Suck at ADC (ADC) from the first lesson"]
    XCTAssertTrue(play.waitForExistence(timeout: 10), "the pinned Play should be on the landscape page")
    XCTAssertTrue(app.staticTexts["Farming Fundamentals"].exists, "the lessons should still be listed")

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "course-landscape"
    shot.lifetime = .keepAlways
    add(shot)
  }

  func testSearchNarrowsTheLibrary() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 40))
    field.tap()
    field.typeText("Ahri")

    XCTAssertTrue(app.staticTexts["Ahri vs Zed"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Why You Suck at ADC (ADC)"].exists)

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "search"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
