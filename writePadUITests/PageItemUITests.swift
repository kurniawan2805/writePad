import XCTest

@MainActor
final class PageItemUITests: XCTestCase {
    func testTextItemEditMoveResizeUndoAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication.isolated()
        app.launch()
        let title = "Page Items \(UUID().uuidString.prefix(6))"
        createNotebook(title, in: app)
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(app.buttons["Items"].waitForExistence(timeout: 5))
        app.buttons["Items"].tap()
        app.buttons["Text Box"].tap()
        let text = app.textViews["Text Box Content"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText(" Hello T9")
        app.buttons["Done"].tap()
        let item = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hello T9")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        let original = item.frame
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: item.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)))
        XCTAssertGreaterThan(item.frame.minX, original.minX + 10)
        app.buttons["Undo"].tap()
        XCTAssertEqual(item.frame.minX, original.minX, accuracy: 3)
        app.buttons["Redo"].tap()
        let moved = item.frame
        let handle = item.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.98))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: 45, dy: 35)))
        XCTAssertGreaterThan(item.frame.width, moved.width + 15)
        let resizedWidth = item.frame.width
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Text item moved and resized"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Library"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        app.buttons["Items"].tap()
        app.descendants(matching: .any).matching(identifier: "Edit Items").firstMatch.tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(item.frame.width, resizedWidth, accuracy: 5)
        item.tap()
        app.buttons["Items"].tap()
        app.buttons["Delete Selected Item"].tap()
        XCTAssertFalse(item.exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testPDFItemMoveZoomAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication.isolated()
        let title = "PDF Items \(UUID().uuidString.prefix(6))"
        let url = URL.temporaryDirectory.appending(path: title + ".pdf")
        try PDFFixture.data(pageCount: 1).write(to: url, options: .atomic)
        app.launch()
        app.open(url)
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.buttons["Items"].waitForExistence(timeout: 5))
        app.buttons["Items"].tap()
        app.buttons["Text Box"].tap()
        let text = app.textViews["Text Box Content"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("PDF overlay")
        app.buttons["Done"].tap()
        let item = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PDF overlay")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        let original = item.frame
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: item.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        XCTAssertGreaterThan(item.frame.minX, original.minX + 10)
        app.otherElements["PDF Reader"].pinch(withScale: 1.3, velocity: 1)
        XCTAssertTrue(item.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PDF page item after move and zoom"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Library"].tap()
        card.tap()
        XCTAssertTrue(app.buttons["Items"].waitForExistence(timeout: 5))
        app.buttons["Items"].tap()
        app.descendants(matching: .any).matching(identifier: "Edit Items").firstMatch.tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
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
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
    }
}
