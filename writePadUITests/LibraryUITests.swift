import XCTest

@MainActor
final class LibraryUITests: XCTestCase {
    func testImportPDFPresentsFilesPicker() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let importButton = app.buttons["Import PDF"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        importButton.tap()

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10))
        attachScreenshot("PDF file picker")
        cancelButton.tap()
    }

    func testNotebookRoundTripThroughLibrary() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let title = "Library Test \(UUID().uuidString.prefix(6))"
        app.launch()

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
        attachScreenshot("Notebook library")
        card.tap()
        XCTAssertTrue(app.buttons["Add Page"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Add Page"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 5))
        attachScreenshot("Notebook editor")
        app.buttons["Library"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.staticTexts["1 / 2"].waitForExistence(timeout: 5))
        app.buttons["Library"].tap()

        card.press(forDuration: 1)
        app.buttons["Rename"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count) + "Renamed " + title)
        app.buttons["Save"].tap()
        let renamedCard = app.buttons.containing(.staticText, identifier: "Renamed " + title).firstMatch
        XCTAssertTrue(renamedCard.waitForExistence(timeout: 5))

        renamedCard.press(forDuration: 1)
        app.buttons["Delete Notebook"].tap()
        app.buttons["Delete Notebook"].tap()
        XCTAssertTrue(renamedCard.waitForNonExistence(timeout: 5))
    }

    func testFolderSearchAndSort() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let suffix = String(UUID().uuidString.prefix(6))
        let folder = "Folder \(suffix)"
        let title = "Course \(suffix)"
        app.launch()
        XCTAssertTrue(app.buttons["New Folder"].waitForExistence(timeout: 15))
        app.buttons["New Folder"].tap()
        fillName(folder, in: app)
        XCTAssertTrue(app.buttons[folder].waitForExistence(timeout: 5))
        app.buttons[folder].tap()
        app.buttons["Create"].tap()
        app.buttons["New Notebook"].firstMatch.tap()
        fillName(title, in: app)
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["Sort"].tap()
        app.buttons["Name"].tap()

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("NoMatch")
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + title.lowercased())
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count))
        attachScreenshot("Folder with notebook")
        card.press(forDuration: 1)
        app.buttons["Move to Folder"].tap()
        app.buttons["No Folder"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        app.buttons["All Notebooks"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.buttons[folder].press(forDuration: 1)
        app.buttons["Rename"].tap()
        fillName(String(repeating: XCUIKeyboardKey.delete.rawValue, count: folder.count) + "Renamed " + folder, in: app)
        let renamed = app.buttons["Renamed " + folder]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.press(forDuration: 1)
        app.buttons["Delete Folder"].tap()
        app.buttons["Delete Folder"].tap()
        XCTAssertTrue(renamed.waitForNonExistence(timeout: 5))
        XCTAssertTrue(card.exists)
        card.press(forDuration: 1)
        app.buttons["Delete Notebook"].tap()
        app.buttons["Delete Notebook"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }

    private func fillName(_ text: String, in app: XCUIApplication) {
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(text)
        app.buttons["Save"].tap()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
