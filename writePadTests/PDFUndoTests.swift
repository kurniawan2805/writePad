import PDFKit
import PencilKit
import Testing
import UIKit
@testable import writePad

@MainActor
struct PDFUndoTests {
    let store: NotebookStore

    init() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
    }

    private func openPDF() throws -> EditorViewModel {
        let url = store.rootURL.appending(path: "Lecture.pdf")
        try PDFFixture.data(pageCount: 2).write(to: url, options: .atomic)
        return try EditorViewModel(store: store, manifest: store.importPDF(from: url, title: "Lecture"))
    }

    /// Undo used to point at the page's canvas, which is released when the page scrolls away.
    @Test func inkUndoReachesAPageWhoseCanvasWasReleased() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        let undo = UndoManager()
        undo.groupsByEvent = false
        pdf.undoManagerOverride = undo
        let coordinator = PDFCanvasView.Coordinator(viewModel: editor, pdf: pdf, controller: CanvasController())
        let view = PDFView()
        let page = try #require(pdf.document.page(at: 0))
        let id = editor.pages[0].id
        let overlay = try #require(coordinator.pdfView(view, overlayViewFor: page) as? PDFPageCanvas)
        #expect(overlay.canvas.undoManager?.canUndo == false)
        undo.beginUndoGrouping()
        overlay.canvas.drawing = NotebookStoreTests.sampleDrawing()
        coordinator.canvasViewDrawingDidChange(overlay.canvas)
        undo.endUndoGrouping()
        #expect(overlay.canvas.undoManager?.canUndo == true, "the canvas forwards to the shared stack")
        coordinator.pdfView(view, willEndDisplayingOverlayView: overlay, for: page)
        #expect(coordinator.overlays.isEmpty)

        undo.undo()
        #expect(editor.drawing(forPage: id).strokes.isEmpty)
        editor.saveNow()
        #expect(try store.loadDrawing(pageID: id, notebookID: editor.manifest.id).strokes.isEmpty)
        undo.redo()
        #expect(editor.drawing(forPage: id).strokes.count == 1)
        let restored = try #require(coordinator.pdfView(view, overlayViewFor: page) as? PDFPageCanvas)
        #expect(restored.canvas.drawing.strokes.count == 1)
        undo.undo()
        #expect(restored.canvas.drawing.strokes.isEmpty, "a visible canvas follows the undo")
    }

    @Test func oneToolGestureIsOneInkUndoStep() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        let undo = UndoManager()
        undo.groupsByEvent = false
        pdf.undoManagerOverride = undo
        let coordinator = PDFCanvasView.Coordinator(viewModel: editor, pdf: pdf, controller: CanvasController())
        let page = try #require(pdf.document.page(at: 0))
        let overlay = try #require(coordinator.pdfView(PDFView(), overlayViewFor: page) as? PDFPageCanvas)
        let stroke = try #require(NotebookStoreTests.sampleDrawing().strokes.first)
        var shifted = stroke
        shifted.transform = CGAffineTransform(translationX: 0, y: 200)
        undo.beginUndoGrouping()
        coordinator.canvasViewDidBeginUsingTool(overlay.canvas)
        for drawing in [PKDrawing(strokes: [stroke]), PKDrawing(strokes: [stroke, shifted])] {
            overlay.canvas.drawing = drawing
            coordinator.canvasViewDrawingDidChange(overlay.canvas)
        }
        coordinator.canvasViewDidEndUsingTool(overlay.canvas)
        undo.endUndoGrouping()
        // PencilKit can report the finished stroke after the gesture ends.
        undo.beginUndoGrouping()
        coordinator.canvasViewDidBeginUsingTool(overlay.canvas)
        coordinator.canvasViewDidEndUsingTool(overlay.canvas)
        overlay.canvas.drawing = PKDrawing()
        coordinator.canvasViewDrawingDidChange(overlay.canvas)
        undo.endUndoGrouping()

        undo.undo()
        #expect(overlay.canvas.drawing.strokes.count == 2)
        undo.undo()
        #expect(overlay.canvas.drawing.strokes.isEmpty)
        #expect(!undo.canUndo)
    }

    @Test func markupEditsUndoAndRedoAndAreSaved() throws {
        let editor = try openPDF()
        let pdf = try #require(editor.pdf)
        let undo = UndoManager()
        undo.groupsByEvent = false
        pdf.undoManagerOverride = undo
        func step(_ change: () -> Void) {
            undo.beginUndoGrouping()
            change()
            undo.endUndoGrouping()
        }
        pdf.search("searchable")
        let selection = try #require(pdf.searchResults.first)
        step { pdf.annotate(selection, kind: .highlight) }
        #expect(undo.undoActionName == "Highlight")
        step { pdf.addComment("Check", pageID: editor.pages[1].id) }
        let comment = try #require(pdf.markups.last)
        step { pdf.updateComment(id: comment.id, text: "Checked") }
        step { pdf.removeMarkup(id: comment.id) }
        #expect(pdf.markups.map(\.kind) == [.highlight])

        undo.undo() // delete
        #expect(pdf.markups.last?.text == "Checked")
        undo.undo() // edit
        #expect(pdf.markups.last?.text == "Check")
        undo.undo() // comment
        undo.undo() // highlight
        #expect(pdf.markups.isEmpty)
        #expect(pdf.document.page(at: 0)?.annotations.isEmpty == true)
        editor.saveNow()
        #expect(try store.loadPDFMarkups(notebookID: editor.manifest.id).isEmpty)

        undo.redo()
        #expect(pdf.markups.map(\.kind) == [.highlight])
        #expect(pdf.document.page(at: 0)?.annotations.count == 1)
        editor.saveNow()
        #expect(try store.loadPDFMarkups(notebookID: editor.manifest.id).map(\.kind) == [.highlight])
    }
}
