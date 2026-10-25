import PDFKit
import PencilKit
import Testing
import UIKit
@testable import writePad

@MainActor
struct PDFNotebookTests {
    let store: NotebookStore

    init() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
    }

    private func openPDF(rotation: Int = 0, count: Int = 2) throws -> EditorViewModel {
        let url = store.rootURL.appending(path: "Lecture.pdf")
        try PDFFixture.data(pageCount: count, rotation: rotation).write(to: url, options: .atomic)
        #expect(PDFDocument(url: url)?.outlineRoot?.numberOfChildren == 1)
        return try EditorViewModel(store: store, manifest: store.importPDF(from: url, title: "Lecture"))
    }

    @Test func searchOutlineAndInsertedPageKeepSourceMapping() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        let originalIDs = editor.pages.map(\.id)
        #expect(pdf.outline.first?.pageID == originalIDs[1])
        pdf.search("searchable")
        #expect(pdf.searchResults.count == 2)
        editor.addPage(after: 0)
        #expect(pdf.document.pageCount == 3)
        #expect(pdf.document.page(at: 1)?.string?.isEmpty != false)
        #expect(pdf.document.page(at: 2)?.string?.contains("Lecture 2") == true)
        editor.movePages(from: [2], to: 0)
        #expect(pdf.document.page(at: 0)?.string?.contains("Lecture 2") == true)
        #expect(pdf.outline.first?.pageID == originalIDs[1])
        editor.saveNow()
        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: editor.manifest.id))
        #expect(reopened.pages.map(\.id) == editor.pages.map(\.id))
        #expect(reopened.pdf?.document.page(at: 0)?.string?.contains("Lecture 2") == true)
    }

    @Test func annotationsCommentsAndPageLocalInkSurviveReopen() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        pdf.search("searchable")
        let selection = try #require(pdf.searchResults.first)
        for kind in [PDFMarkup.Kind.highlight, .underline, .strikeOut] {
            #expect(pdf.annotate(selection, kind: kind) > 0)
        }
        let id = editor.pages[0].id
        pdf.addComment("Review this", pageID: id)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing(), pageID: id)
        editor.saveNow()
        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: editor.manifest.id))
        #expect(reopened.pdf?.markups == pdf.markups)
        #expect(reopened.pdf?.page(for: id)?.annotations.filter { $0.type != "Popup" }.count == 4)
        #expect(reopened.drawing(forPage: id).strokes.count == 1)
        #expect(reopened.drawing(forPage: editor.pages[1].id).strokes.isEmpty)
        let comment = try #require(reopened.pdf?.markups.first { $0.kind == .comment })
        reopened.pdf?.updateComment(id: comment.id, text: "Reviewed")
        reopened.saveNow()
        #expect(try store.loadPDFMarkups(notebookID: editor.manifest.id).last?.text == "Reviewed")
        reopened.pdf?.removeMarkup(id: comment.id)
        reopened.saveNow()
        #expect(try store.loadPDFMarkups(notebookID: editor.manifest.id).count == 3)
    }

    @Test func failedAnnotationWriteKeepsChangesForRetry() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        let url = store.packageURL(for: editor.manifest.id).appending(path: "annotations.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        pdf.addComment("Do not lose me", pageID: editor.pages[0].id)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing(), pageID: editor.pages[0].id)
        editor.saveNow()
        #expect(editor.lastError != nil)
        try FileManager.default.removeItem(at: url)
        editor.saveNow()
        #expect(editor.lastError == nil)
        #expect(try store.loadPDFMarkups(notebookID: editor.manifest.id).first?.text == "Do not lose me")
        #expect(try store.loadDrawing(pageID: editor.pages[0].id, notebookID: editor.manifest.id).strokes.count == 1)
    }

    @Test func deletedPageAnnotationsDoNotMoveToAnotherPage() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        pdf.addComment("Page two", pageID: editor.pages[1].id)
        editor.deletePage(at: 1)
        #expect(pdf.document.page(at: 0)?.annotations.isEmpty == true)
        editor.saveNow()
        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: editor.manifest.id))
        #expect(reopened.pdf?.document.pageCount == 1)
        #expect(reopened.pdf?.document.page(at: 0)?.annotations.isEmpty == true)
        #expect(try store.loadPDFMarkups(notebookID: editor.manifest.id).isEmpty)
    }

    @Test func orphanedAnnotationsFromOlderSavesArePrunedOnOpen() throws {
        let editor = try openPDF()
        let kept = PDFMarkup(pageID: editor.pages[0].id, kind: .comment, bounds: CGRect(x: 10, y: 10, width: 24, height: 24), text: "Kept")
        let orphan = PDFMarkup(pageID: UUID(), kind: .comment, bounds: CGRect(x: 10, y: 10, width: 24, height: 24), text: "Orphan")
        try store.savePDFMarkups([kept, orphan], notebookID: editor.manifest.id)

        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: editor.manifest.id))
        #expect(reopened.pdf?.markups.map(\.text) == ["Kept"])
        reopened.saveNow()
        #expect(try store.loadPDFMarkups(notebookID: editor.manifest.id).map(\.text) == ["Kept"])
    }

    @Test func olderPDFWithoutAnnotationSidecarOpensAndUpgradesOnSave() throws {
        let editor = try openPDF()
        var manifest = editor.manifest
        manifest.version = 2
        try store.saveManifest(manifest)
        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: manifest.id))
        #expect(reopened.pdf?.markups.isEmpty == true)
        reopened.pdf?.addComment("New format", pageID: manifest.pages[0].id)
        reopened.saveNow()
        #expect(try store.loadManifest(id: manifest.id).version == NotebookManifest.currentVersion)
    }

    @Test(arguments: [0, 90, 180, 270])
    func overlayUsesDisplayedPagePointsAcrossZoom(rotation: Int) throws {
        let editor = try openPDF(rotation: rotation)
        let page = try #require(editor.pdf?.document.page(at: 0))
        let size = PDFPageCanvas.displaySize(for: page)
        #expect(size == (rotation % 180 == 0 ? CGSize(width: 612, height: 792) : CGSize(width: 792, height: 612)))
        let overlay = PDFPageCanvas(size: size)
        overlay.canvas.drawing = NotebookStoreTests.sampleDrawing()
        let bounds = overlay.canvas.drawing.bounds
        for scale in [0.5, 1, 3.0] {
            overlay.frame = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
            overlay.layoutIfNeeded()
            #expect(overlay.canvas.bounds.size == size)
            #expect(overlay.canvas.drawing.bounds == bounds)
        }
    }

    @Test func missingSourceFailsInsteadOfOpeningBlankNotebook() throws {
        let editor = try openPDF()
        try FileManager.default.removeItem(at: store.sourcePDFURL(for: editor.manifest.id))
        #expect(throws: NotebookStore.StoreError.invalidPDF) {
            try EditorViewModel(store: store, manifest: editor.manifest)
        }
    }

    @Test func corruptAnnotationsFailWithoutOverwritingTheSidecar() throws {
        let editor = try openPDF()
        let url = store.packageURL(for: editor.manifest.id).appending(path: "annotations.json")
        let corrupt = Data("broken annotations".utf8)
        try corrupt.write(to: url, options: .atomic)
        #expect(throws: (any Error).self) { try EditorViewModel(store: store, manifest: editor.manifest) }
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func sourceStickyNotesAreListedWithoutDuplicatingThemInStorage() throws {
        let editor = try openPDF()
        let url = store.sourcePDFURL(for: editor.manifest.id)
        let source = try #require(PDFDocument(url: url))
        let note = PDFAnnotation(bounds: CGRect(x: 40, y: 600, width: 24, height: 24), forType: .text, withProperties: nil)
        note.contents = "Original note"
        source.page(at: 0)?.addAnnotation(note)
        try #require(source.dataRepresentation()).write(to: url, options: .atomic)
        let reopened = try EditorViewModel(store: store, manifest: editor.manifest)
        #expect(reopened.pdf?.sourceComments.first?.text == "Original note")
        #expect(reopened.pdf?.sourceComments.first?.pageID == editor.pages[0].id)
        #expect(reopened.pdf?.markups.isEmpty == true)
    }

    @Test func invalidSourcePageReferenceFailsInsteadOfSubstitutingBlankPaper() throws {
        let editor = try openPDF()
        var manifest = editor.manifest
        manifest.pages[0].pdfPageIndex = 9
        #expect(throws: NotebookStore.StoreError.invalidPDF) { try EditorViewModel(store: store, manifest: manifest) }
    }

    @Test func offscreenCanvasIsReleasedAndRestoresSavedPageCoordinates() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        let coordinator = PDFCanvasView.Coordinator(viewModel: editor, pdf: pdf, controller: CanvasController())
        let view = PDFView()
        let page = try #require(pdf.document.page(at: 0))
        let overlay = try #require(coordinator.pdfView(view, overlayViewFor: page) as? PDFPageCanvas)
        overlay.canvas.drawing = NotebookStoreTests.sampleDrawing()
        coordinator.canvasViewDrawingDidChange(overlay.canvas)
        coordinator.pdfView(view, willEndDisplayingOverlayView: overlay, for: page)
        #expect(coordinator.overlays.isEmpty)
        let restored = try #require(coordinator.pdfView(view, overlayViewFor: page) as? PDFPageCanvas)
        #expect(restored !== overlay)
        #expect(restored.canvas.drawing.bounds == NotebookStoreTests.sampleDrawing().bounds)
        editor.saveNow()
        #expect(try store.loadDrawing(pageID: editor.pages[0].id, notebookID: editor.manifest.id).strokes.count == 1)
    }
}
