import XCTest

@MainActor
final class ExportUITests: XCTestCase {
    func testExportPDFAndPNGPresentShareSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let title = "Export Test \(UUID().uuidString.prefix(6))"
        XCTAssertTrue(app.buttons["Create"].waitForExistence(timeout: 15))
        app.buttons["Create"].tap()
        app.buttons["New Notebook"].firstMatch.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(title)
        app.buttons["Save"].tap()
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 5))
        app.buttons["Add Page"].tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 5))

        for option in ["Export PDF", "Export Current Page as PNG"] {
            app.buttons["Export"].tap()
            app.buttons[option].tap()
            XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 15))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = option
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 5))
        }
        app.buttons["Library"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1)
        app.buttons["Delete Notebook"].tap()
        app.buttons["Delete Notebook"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }
}
