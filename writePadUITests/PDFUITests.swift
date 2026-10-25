import PDFKit
import UIKit
import XCTest

@MainActor
final class PDFUITests: XCTestCase {
    func testPDFReadingAnnotationsAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication.isolated()
        let title = "PDF Test \(UUID().uuidString.prefix(6))"
        let url = try fixture(title: title)
        // Launch first so the isolated storage environment applies before the file is opened.
        app.launch()
        app.open(url)
        let imported = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 15))
        imported.tap()
        XCTAssertTrue(app.buttons["PDF Tools"].waitForExistence(timeout: 15))
        screenshot("PDF reader")

        app.buttons["PDF Tools"].tap()
        app.buttons["Highlight Selection"].tap()
        XCTAssertTrue(app.alerts["Select PDF text first"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()

        showNavigation(in: app)
        selectNavigation("Outline", in: app)
        XCTAssertTrue(app.buttons["Chapter Two"].waitForExistence(timeout: 5))
        app.buttons["Chapter Two"].tap()
        XCTAssertTrue(app.pageIndicator(2, of: 2).waitForExistence(timeout: 5))
        hideNavigation(in: app)
        app.buttons["Add Page"].firstMatch.tap()
        XCTAssertTrue(app.pageIndicator(3, of: 3).waitForExistence(timeout: 5), app.debugDescription)
        showNavigation(in: app)
        selectNavigation("Search", in: app)
        let search = app.textFields["Search PDF Text"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("searchable")
        let result = app.buttons["PDF Search Result 1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        hideNavigation(in: app)
        app.buttons["PDF Tools"].tap()
        app.buttons["Highlight Selection"].tap()

        app.buttons["PDF Tools"].tap()
        app.buttons["Add Comment"].tap()
        let comment = app.textViews["Comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()
        comment.typeText("Review this lecture")
        app.buttons["Save Comment"].tap()
        showNavigation(in: app)
        selectNavigation("Comments", in: app)
        XCTAssertTrue(app.staticTexts["Review this lecture"].waitForExistence(timeout: 5))
        screenshot("PDF annotations")
        hideNavigation(in: app)

        drawAndReopen(app, title: title)
        verifyReopenedAnnotationsAndExport(app, title: title)
    }

    /// Undo used to do nothing once the page with the stroke had scrolled away, and never reverted a highlight.
    func testUndoReachesInkOnAnotherPageAndHighlights() throws {
        continueAfterFailure = false
        let app = XCUIApplication.isolated()
        let title = "PDF Undo \(UUID().uuidString.prefix(6))"
        let url = URL.temporaryDirectory.appending(path: title + ".pdf")
        try PDFFixture.data(pageCount: 6).write(to: url, options: .atomic)
        app.launch()
        app.open(url)
        let imported = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 15))
        imported.tap()
        XCTAssertTrue(app.pageIndicator(1, of: 6).waitForExistence(timeout: 15))
        let reader = app.otherElements["PDF Reader"]
        sleep(2) // let the reader fit the page before drawing

        app.buttons["Draw on PDF"].tap()
        reader.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: reader.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)))
        sleep(1)
        screenshot("Stroke drawn on page 1")
        app.buttons["Draw on PDF"].tap()
        for _ in 0..<8 { reader.swipeUp(velocity: .fast) }
        XCTAssertTrue(app.pageIndicator(1, of: 6).waitForNonExistence(timeout: 5))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.pageIndicator(1, of: 6).waitForExistence(timeout: 5), "undo shows the page it changed")
        sleep(1)
        screenshot("Stroke undone on page 1")
        app.buttons["Redo"].tap()
        sleep(1)
        screenshot("Stroke redone on page 1")

        showNavigation(in: app)
        selectNavigation("Search", in: app)
        let search = app.textFields["Search PDF Text"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Lecture 1")
        app.buttons["PDF Search Result 1"].tap()
        hideNavigation(in: app)
        app.buttons["PDF Tools"].tap()
        app.buttons["Highlight Selection"].tap()
        showNavigation(in: app)
        selectNavigation("Comments", in: app)
        XCTAssertTrue(app.staticTexts["Lecture 1"].waitForExistence(timeout: 5))
        hideNavigation(in: app)
        app.buttons["Undo"].tap()
        showNavigation(in: app)
        XCTAssertTrue(app.staticTexts["No annotations yet."].waitForExistence(timeout: 5))
        hideNavigation(in: app)
        app.buttons["Redo"].tap()
        showNavigation(in: app)
        XCTAssertTrue(app.staticTexts["Lecture 1"].waitForExistence(timeout: 5))
    }

    private func drawAndReopen(_ app: XCUIApplication, title: String) {
        app.buttons["Draw on PDF"].tap()
        XCTAssertTrue(app.buttons["Favorite Pen 1"].waitForExistence(timeout: 5))
        let reader = app.otherElements["PDF Reader"]
        let start = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.3))
        let end = reader.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
        screenshot("Handwriting on PDF")
        app.buttons["Draw on PDF"].tap()
        app.buttons["Library"].tap()
        app.terminate()
        app.launch()
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.buttons["PDF Tools"].waitForExistence(timeout: 5))
    }

    private func verifyReopenedAnnotationsAndExport(_ app: XCUIApplication, title: String) {
        showNavigation(in: app)
        selectNavigation("Comments", in: app)
        XCTAssertTrue(app.staticTexts["Review this lecture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["searchable"].exists)
        screenshot("Reopened PDF with annotations and ink")
        hideNavigation(in: app)
        app.buttons["Export"].tap()
        app.buttons["Export PDF"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 15))
        screenshot("Annotated PDF export")
        app.buttons["Close"].firstMatch.tap()
        app.buttons["Library"].tap()
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1)
        app.buttons["Delete Notebook"].tap()
        app.buttons["Delete Notebook"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
    }

    private func showNavigation(in app: XCUIApplication) {
        app.buttons["PDF Tools"].tap()
        app.buttons["Pages, Outline, Search & Comments"].tap()
    }

    private func hideNavigation(in app: XCUIApplication) {
        let buttons = app.buttons.matching(identifier: "Hide Sidebar")
        guard let hide = buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("No visible sidebar toggle. \(app.debugDescription)")
            return
        }
        hide.tap()
    }

    private func selectNavigation(_ title: String, in app: XCUIApplication) {
        app.buttons.matching(identifier: "PDF Navigation").firstMatch.tap()
        app.buttons[title].firstMatch.tap()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fixture(title: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: title + ".pdf")
        try PDFFixture.data().write(to: url, options: .atomic)
        return url
    }
}
