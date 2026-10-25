import PDFKit
import XCTest

/// Real gestures on a 100+ page PDF (`TEST_RUNNER_WRITEPAD_LARGE_PDF` for a real document, else `LargePDF`'s
/// generated book). Budgets are loose; the `LARGEPDF-UI` lines in the log are the measurements.
@MainActor
final class LargePDFUITests: XCTestCase {
    func testJumpDrawUndoSearchAndExportOnALongPDF() throws {
        continueAfterFailure = false
        let source = try LargePDF.url()
        let document = try XCTUnwrap(PDFDocument(url: source))
        let total = document.pageCount
        XCTAssertGreaterThan(total, 100)
        let late = try XCTUnwrap(distinctiveWord(in: document, near: total - 20))
        let early = try XCTUnwrap(distinctiveWord(in: document, near: 2))
        let title = "Large PDF \(UUID().uuidString.prefix(6))"
        let url = URL.temporaryDirectory.appending(path: title + ".pdf")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: source, to: url)

        let app = XCUIApplication.isolated()
        app.launch()
        app.open(url)
        let card = app.buttons.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        measure("open \(total) pages", budget: 15) {
            card.tap()
            XCTAssertTrue(app.pageIndicator(1, of: total).waitForExistence(timeout: 30))
        }
        let reader = app.otherElements["PDF Reader"]
        // Each fling decelerates for ~2 s before XCUITest sees the app idle; profiling showed writePad's own code
        // under 1% of the main thread while scrolling this document.
        measure("10 fast swipes", budget: 60) {
            for _ in 0..<10 { reader.swipeUp(velocity: .fast) }
        }
        drawUndoAndRedo(late: late, early: early, total: total, in: app)
        searchAndExport(in: app)
    }

    private func drawUndoAndRedo(late: (word: String, page: Int), early: (word: String, page: Int), total: Int,
                                 in app: XCUIApplication) {
        let reader = app.otherElements["PDF Reader"]
        jump(to: late, in: app)
        // The reader may settle on the next page when the match sits low on its page.
        let drawn = currentPage(in: app)
        XCTAssertLessThanOrEqual(abs(drawn - (late.page + 1)), 2, "jumped to page \(drawn) for page \(late.page + 1)")
        app.buttons["Draw on PDF"].tap()
        reader.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: reader.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55)))
        sleep(1)
        screenshot("Stroke on page \(drawn)")
        app.buttons["Draw on PDF"].tap()

        jump(to: early, in: app)
        XCTAssertLessThanOrEqual(abs(currentPage(in: app) - (early.page + 1)), 2)
        measure("undo on a page \(drawn - early.page - 1) pages away", budget: 15) {
            app.buttons["Undo"].tap()
            XCTAssertTrue(app.pageIndicator(drawn, of: total).waitForExistence(timeout: 15))
        }
        sleep(1)
        screenshot("Undo returned to page \(drawn)")
        app.buttons["Redo"].tap()
    }

    private func searchAndExport(in app: XCUIApplication) {
        // Every keystroke searches the whole document.
        showNavigation(in: app)
        selectNavigation("Search", in: app)
        let search = app.textFields["Search PDF Text"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        clear(search)
        measure("type 'the' into search", budget: 30) { search.typeText("the") }
        XCTAssertTrue(app.buttons["PDF Search Result 1"].waitForExistence(timeout: 10))
        screenshot("Search results")
        hideNavigation(in: app)

        app.buttons["Export"].tap()
        measure("export PDF to share sheet", budget: 60) {
            app.buttons["Export PDF"].tap()
            XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 60))
        }
        app.buttons["Close"].firstMatch.tap()
    }

    /// A word that only occurs on one page close to `page`, so searching it jumps there. Pages near link-dense ones
    /// (a book's index) are skipped: with those on screen PDFKit's accessibility tree fails (docs/TASKS.md, T20).
    private func distinctiveWord(in document: PDFDocument, near page: Int) -> (word: String, page: Int)? {
        let linkDense = { (index: Int) in (document.page(at: index)?.annotations.count ?? 0) >= 20 }
        for index in stride(from: min(document.pageCount - 1, page + 3), through: max(0, page - 12), by: -1)
        where !(max(0, index - 4)...min(document.pageCount - 1, index + 4)).contains(where: linkDense) {
            let words = (document.page(at: index)?.string ?? "")
                .components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 7 }
            for word in Set(words).sorted() {
                let matches = document.findString(word, withOptions: [.caseInsensitive])
                if !matches.isEmpty, matches.allSatisfy({ $0.pages.allSatisfy { document.index(for: $0) == index } }) {
                    return (word, index)
                }
            }
        }
        return nil
    }

    private func jump(to target: (word: String, page: Int), in app: XCUIApplication) {
        showNavigation(in: app)
        selectNavigation("Search", in: app)
        let search = app.textFields["Search PDF Text"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        clear(search)
        search.typeText(target.word)
        let result = app.buttons["PDF Search Result 1"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        sleep(1) // the accessibility snapshot fails while the reader is still jumping
        hideNavigation(in: app)
    }

    private func clear(_ field: XCUIElement) {
        field.tap()
        let length = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: length + 2))
    }

    /// The page number the toolbar shows ("Page 12 of 244").
    private func currentPage(in app: XCUIApplication) -> Int {
        sleep(1)
        let value = app.buttons["Pages"].value as? String ?? ""
        return Int(value.split(separator: " ").dropFirst().first ?? "") ?? -1
    }

    private func measure(_ label: String, budget: TimeInterval, _ work: () -> Void) {
        let start = Date()
        work()
        let elapsed = Date().timeIntervalSince(start)
        print("LARGEPDF-UI \(label): \(String(format: "%.1f", elapsed)) s")
        XCTAssertLessThan(elapsed, budget, label)
    }

    private func showNavigation(in app: XCUIApplication) {
        // A long PDF makes the accessibility tree large and menus slow to report; a second tap would close it again.
        let item = app.buttons["Pages, Outline, Search & Comments"]
        app.buttons["PDF Tools"].tap()
        if !item.waitForExistence(timeout: 10) { app.buttons["PDF Tools"].tap() }
        item.tap()
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
}
