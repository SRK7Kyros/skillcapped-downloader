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

  func testACatalogueCoursePageUsesTheCourseDesign() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary", "-demoCatalog"]
    app.launch()

    let tab = app.tabBars.buttons["Discover"]
    XCTAssertTrue(tab.waitForExistence(timeout: 40), "the Discover tab should be there")
    tab.tap()

    let course = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(course.waitForExistence(timeout: 30), "the catalogue card should render")
    course.tap()

    let play = app.buttons["Play Why You Suck at ADC (ADC) from the first lesson"]
    XCTAssertTrue(play.waitForExistence(timeout: 15), "a course already here should offer Play on its hero")
    XCTAssertTrue(app.staticTexts["Not On This Phone"].waitForExistence(timeout: 10), "the catalogue's lessons should be listed")

    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }

    XCTAssertTrue(play.waitForExistence(timeout: 10), "the pinned Play should survive landscape")
    XCTAssertTrue(app.staticTexts["Not On This Phone"].exists, "the lessons should still be listed")

    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "catalogue-course-landscape"
    shot.lifetime = .keepAlways
    add(shot)
  }

  /// The two course pages are one page, so a lesson row must start at the same
  /// edge and be the same width whichever surface opened it. They used to be two
  /// screens that merely looked alike, and the rows sat four points apart.
  func testBothCoursePagesDrawTheSameLessonRow() {
    let app = XCUIApplication()
    app.launchArguments = ["-demoLibrary"]
    app.launch()

    let card = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(card.waitForExistence(timeout: 40), "the course card should render")
    card.tap()
    XCTAssertTrue(app.staticTexts["Farming Fundamentals"].waitForExistence(timeout: 15))

    let libraryRow = app.buttons.matching(identifier: "course.lesson").firstMatch
    XCTAssertTrue(libraryRow.waitForExistence(timeout: 10), "the library page should list a lesson row")
    let library = libraryRow.frame
    XCTAssertGreaterThan(library.width, 200, "a lesson row should span the page")

    app.terminate()

    app.launchArguments = ["-demoLibrary", "-demoCatalog"]
    app.launch()
    let tab = app.tabBars.buttons["Discover"]
    XCTAssertTrue(tab.waitForExistence(timeout: 40), "the Discover tab should be there")
    tab.tap()

    let catalogueCard = app.staticTexts["Why You Suck at ADC (ADC)"]
    XCTAssertTrue(catalogueCard.waitForExistence(timeout: 30), "the catalogue card should render")
    catalogueCard.tap()
    XCTAssertTrue(app.staticTexts["Not On This Phone"].waitForExistence(timeout: 15))

    let catalogueRow = app.buttons.matching(identifier: "course.lesson").firstMatch
    XCTAssertTrue(catalogueRow.waitForExistence(timeout: 10), "the catalogue page should list a lesson row")
    let catalogue = catalogueRow.frame
    XCTAssertGreaterThan(catalogue.width, 200, "a lesson row should span the page")

    XCTAssertEqual(
      library.minX,
      catalogue.minX,
      accuracy: 1,
      "a lesson row should start at the same edge on both pages"
    )
    XCTAssertEqual(
      library.width,
      catalogue.width,
      accuracy: 1,
      "and be exactly as wide"
    )
  }
}
