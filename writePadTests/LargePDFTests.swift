import PDFKit
import PencilKit
import Testing
import UIKit
@testable import writePad

/// Scale checks on a 100+ page PDF (a real document via `WRITEPAD_LARGE_PDF`, else `LargePDF`'s generated book).
/// Time budgets are loose so a busy simulator passes; the printed `LARGEPDF` lines are the real measurements.
@MainActor
@Suite(.serialized)
struct LargePDFTests {
    let store: NotebookStore

    init() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
    }

    private func measure<T>(_ label: String, budget: Duration, _ work: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let result = try work()
        let elapsed = ContinuousClock.now - start
        print("LARGEPDF \(label): \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
        #expect(elapsed < budget, "\(label) took \(elapsed)")
        return result
    }

    private func open() throws -> (EditorViewModel, PDFNotebook) {
        let source = try LargePDF.url()
        let manifest = try measure("import", budget: .seconds(5)) { try store.importPDF(from: source, title: "Large") }
        let editor = try measure("open", budget: .seconds(5)) { try EditorViewModel(store: store, manifest: manifest) }
        let pdf = try #require(editor.pdf)
        print("LARGEPDF source: \(source.lastPathComponent), \(editor.pages.count) pages, \(pdf.outline.count) outline items")
        #expect(editor.pages.count > 100)
        return (editor, pdf)
    }

    @Test func openSearchAndThumbnailsStayResponsive() async throws {
        let (editor, pdf) = try open()
        #expect(pdf.document.pageCount == editor.pages.count)
        let sourceChapters = try #require(PDFDocument(url: LargePDF.url())).outlineRoot?.numberOfChildren ?? 0
        #expect(pdf.outline.count >= sourceChapters, "the PDF's own outline is listed")
        // The search field searches on every keystroke, on the main actor: "t", "th", "the".
        for prefix in ["t", "th"] {
            measure("search '\(prefix)'", budget: .seconds(10)) { pdf.search(prefix) }
            print("LARGEPDF search '\(prefix)' results: \(pdf.searchResults.count)")
        }
        measure("search '\(LargePDF.searchTerm)'", budget: .seconds(10)) { pdf.search(LargePDF.searchTerm) }
        print("LARGEPDF search results: \(pdf.searchResults.count)")
        #expect(pdf.searchResults.count > editor.pages.count / 2)
        let lastPage = try #require(pdf.searchResults.last?.pages.first)
        #expect(pdf.document.index(for: lastPage) > editor.pages.count / 2)

        let start = ContinuousClock.now
        await editor.waitForThumbnails()
        let elapsed = ContinuousClock.now - start
        print("LARGEPDF all thumbnails: \(elapsed)")
        #expect(editor.thumbnails.count == editor.pages.count)
        #expect(elapsed < .seconds(60))
    }

    @Test func inkAndMarkupsDeepInTheDocumentSurviveReopenAndPageEdits() throws {
        let (editor, pdf) = try open()
        let last = editor.pages.count - 1
        let lastID = editor.pages[last].id, earlyID = editor.pages[5].id
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing(), pageID: lastID)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing(), pageID: earlyID)
        pdf.search(LargePDF.searchTerm)
        let late = try #require(pdf.searchResults.last)
        #expect(pdf.annotate(late, kind: .highlight) > 0)
        pdf.addComment("End of the book", pageID: lastID)
        measure("save", budget: .seconds(5)) { editor.saveNow() }
        #expect(editor.lastError == nil)

        // Page edits rebuild the whole PDF document; each must stay quick and keep the source mapping.
        let lastText = pdf.document.page(at: last)?.string
        measure("add page", budget: .seconds(3)) { editor.addPage(after: 100) }
        measure("delete page", budget: .seconds(3)) { editor.deletePage(at: 0) }
        measure("move page", budget: .seconds(3)) { editor.movePages(from: [0], to: 50) }
        #expect(pdf.document.pageCount == editor.pages.count)
        let movedLast = try #require(editor.pages.firstIndex { $0.id == lastID })
        #expect(pdf.document.page(at: movedLast)?.string == lastText)
        measure("save after page edits", budget: .seconds(5)) { editor.saveNow() }

        let reopened = try measure("reopen", budget: .seconds(5)) {
            try EditorViewModel(store: store, manifest: store.loadManifest(id: editor.manifest.id))
        }
        #expect(reopened.pages.map(\.id) == editor.pages.map(\.id))
        #expect(reopened.drawing(forPage: lastID).strokes.count == 1)
        #expect(reopened.drawing(forPage: earlyID).strokes.count == 1)
        #expect(reopened.pdf?.markups == pdf.markups)
        let reopenedLast = try #require(reopened.pages.firstIndex { $0.id == lastID })
        #expect(reopened.pdf?.document.page(at: reopenedLast)?.string == lastText)
    }

    @Test func exportKeepsEveryPageAndStaysCompact() async throws {
        let (editor, pdf) = try open()
        let lastID = try #require(editor.pages.last?.id)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing(), pageID: lastID)
        pdf.addComment("Last page note", pageID: lastID)
        let start = ContinuousClock.now
        let url = try await editor.export(as: .pdf, directory: store.rootURL)
        let elapsed = ContinuousClock.now - start
        let sourceSize = try #require(try store.sourcePDFURL(for: editor.manifest.id)
            .resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let exportSize = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        print("LARGEPDF export: \(elapsed), \(sourceSize / 1024) KB source → \(exportSize / 1024) KB exported")
        #expect(elapsed < .seconds(60))
        let output = try #require(PDFDocument(url: url))
        #expect(output.pageCount == editor.pages.count)
        #expect(output.page(at: output.pageCount - 1)?.annotations.contains { $0.contents == "Last page note" } == true)
        #expect(output.page(at: 10)?.string?.isEmpty == false, "exported pages keep their text")
        #expect(exportSize < max(sourceSize * 4, 4_000_000), "exporting must not balloon the file")
    }
}
