import XCTest

@MainActor
final class MultipleWindowUITests: XCTestCase {
    func testOpeningSameNotebookInAnotherWindowIsReadOnly() {
        continueAfterFailure = false
        let app = XCUIApplication.isolated()
        app.launch()
        XCTAssertTrue(app.buttons["New Window"].waitForExistence(timeout: 15))
        app.buttons["Create"].tap()
        app.buttons["New Notebook"].firstMatch.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Two Windows")
        app.buttons["Save"].tap()
        let card = app.buttons.containing(.staticText, identifier: "Two Windows").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["Windows"].waitForExistence(timeout: 5))
        app.buttons["Windows"].tap()
        app.buttons["Open in New Window"].tap()
        XCTAssertTrue(app.staticTexts["Read-Only"].waitForExistence(timeout: 15), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Second notebook window is read-only"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
