import XCTest

@MainActor
final class PageUITests: XCTestCase {
    func testTemplatesAndBookmarkFilterSurviveReopen() {
        continueAfterFailure = false
        let app = XCUIApplication.isolated()
        app.launch()
        let title = "Page Tools \(UUID().uuidString.prefix(6))"
        createNotebook(title, in: app)
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["Paper"].waitForExistence(timeout: 5))
        for template in ["Cornell", "Music Staff", "Weekly Planner"] {
            app.buttons["Paper"].tap()
            app.buttons[template].tap()
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = template
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.buttons["Add Page"].firstMatch.tap()
        XCTAssertTrue(app.pageIndicator(2, of: 2).waitForExistence(timeout: 5))
        app.buttons["Bookmark Page"].tap()
        XCTAssertTrue(app.buttons["Remove Bookmark"].exists)
        app.buttons["Add Page"].firstMatch.tap()
        XCTAssertTrue(app.pageIndicator(3, of: 3).waitForExistence(timeout: 5))
        showSidebar(in: app)
        app.segmentedControls.buttons["Bookmarked"].tap()
        let second = app.buttons["Page 2"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Page 1"].exists)
        XCTAssertFalse(app.buttons["Page 3"].exists)
        second.tap()
        XCTAssertTrue(app.pageIndicator(2, of: 3).waitForExistence(timeout: 5))
        hideSidebar(in: app)
        app.buttons["Library"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        showSidebar(in: app)
        app.segmentedControls.buttons["Bookmarked"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.press(forDuration: 1)
        app.buttons["Remove Bookmark"].tap()
        XCTAssertTrue(app.staticTexts["No Bookmarked Pages"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["All"].tap()
        XCTAssertTrue(app.buttons["Page 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Page 3"].exists)
    }

    private func createNotebook(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Create"].waitForExistence(timeout: 15))
        app.buttons["Create"].tap()
        app.buttons["New Notebook"].firstMatch.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(title)
        app.buttons["Save"].tap()
    }

    private func showSidebar(in app: XCUIApplication) {
        let show = app.buttons.matching(identifier: "Show Sidebar").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(show, app.debugDescription)
        show?.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Bookmarked"].waitForExistence(timeout: 5))
    }

    private func hideSidebar(in app: XCUIApplication) {
        let hide = app.buttons.matching(identifier: "Hide Sidebar").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(hide, app.debugDescription)
        hide?.tap()
    }
}
