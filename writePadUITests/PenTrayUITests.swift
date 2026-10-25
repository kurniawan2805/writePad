import XCTest

@MainActor
final class PenTrayUITests: XCTestCase {
    func testFavoriteTrayPersistsAfterToolSwitch() {
        continueAfterFailure = false
        let app = XCUIApplication.isolated()
        app.launch()
        XCTAssertTrue(app.buttons["Create"].waitForExistence(timeout: 15))
        app.buttons["Create"].tap()
        app.buttons["New Notebook"].firstMatch.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Favorite Pens")
        app.buttons["Save"].tap()
        let card = app.buttons.containing(.staticText, identifier: "Favorite Pens").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["Favorite Pen 1"].waitForExistence(timeout: 5))
        app.buttons["Eraser"].tap()
        XCTAssertTrue(app.buttons["Eraser"].isSelected)
        app.buttons["Lasso"].tap()
        XCTAssertTrue(app.buttons["Lasso"].isSelected)
        app.buttons["Favorite Pen 2"].tap()
        app.buttons["Pen Settings"].tap()
        XCTAssertTrue(app.buttons["Add Favorite"].waitForExistence(timeout: 5))
        app.buttons["Add Favorite"].tap()
        app.sliders["Pen Width"].adjust(toNormalizedSliderPosition: 0.3)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Favorite Pen 4"].waitForExistence(timeout: 5))
        let value = app.buttons["Favorite Pen 4"].value as? String
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Custom favorite pen tray"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Library"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.buttons["Favorite Pen 4"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Favorite Pen 4"].value as? String, value)
    }
}
