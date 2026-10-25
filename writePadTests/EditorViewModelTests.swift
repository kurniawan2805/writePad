import Foundation
import PencilKit
import Testing
@testable import writePad

@MainActor
struct EditorViewModelTests {
    let store: NotebookStore

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
    }

    private func reopen(_ editor: EditorViewModel) throws -> EditorViewModel {
        editor.saveNow()
        return try EditorViewModel.openDefault(store: store)
    }

    @Test func savesDrawingAndReopens() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing())

        let reopened = try reopen(editor)
        #expect(reopened.manifest.id == editor.manifest.id)
        #expect(reopened.drawing(forPage: reopened.pages[0].id).strokes.count == 1)
    }

    @Test func inkOnSecondPageIsSavedToThatPage() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.addPage()
        let layout = PageLayout(pageCount: 2)
        let point = layout.frame(ofPage: 1).origin.applying(CGAffineTransform(translationX: 200, y: 200))
        editor.drawingDidChange(PKDrawing(strokes: [PageLayoutTests.stroke(at: point)]))

        let reopened = try reopen(editor)
        #expect(reopened.pages.count == 2)
        #expect(reopened.drawing(forPage: reopened.pages[0].id).strokes.isEmpty)
        #expect(reopened.drawing(forPage: reopened.pages[1].id).strokes.count == 1)
    }

    @Test func addedPageInheritsPaperAndIsInsertedAfterCurrent() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.setBackground(.grid, forPageAt: 0)
        editor.addPage()
        editor.addPage(after: 0)

        #expect(editor.pages.count == 3)
        #expect(editor.pages.allSatisfy { $0.background == .grid })
        #expect(editor.currentPageIndex == 1)
    }

    @Test func reorderAndPaperArePersisted() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.addPage()
        editor.setBackground(.lined, forPageAt: 1)
        let order = editor.pages.map(\.id)
        editor.movePages(from: [1], to: 0)

        let reopened = try reopen(editor)
        #expect(reopened.pages.map(\.id) == [order[1], order[0]])
        #expect(reopened.pages[0].background == .lined)
    }

    @Test func deletingPageRemovesItsDrawingFile() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.addPage()
        let doomed = editor.pages[1].id
        let point = PageLayout(pageCount: 2).frame(ofPage: 1).origin.applying(CGAffineTransform(translationX: 50, y: 50))
        editor.drawingDidChange(PKDrawing(strokes: [PageLayoutTests.stroke(at: point)]))
        editor.saveNow()
        let file = store.packageURL(for: editor.manifest.id).appending(path: "pages/\(doomed.uuidString).drawing")
        #expect(FileManager.default.fileExists(atPath: file.path()))

        editor.deletePage(at: 1)
        let reopened = try reopen(editor)
        #expect(reopened.pages.map(\.id) == [editor.pages[0].id])
        #expect(!FileManager.default.fileExists(atPath: file.path()))
    }

    @Test func lastPageCannotBeDeleted() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.deletePage(at: 0)
        #expect(editor.pages.count == 1)
    }

    @Test func thumbnailsExistForEveryPage() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.addPage()
        #expect(editor.pages.allSatisfy { editor.thumbnails[$0.id] != nil })
    }

    @Test func failedManifestSaveCanBeRetriedAfterDrawingWasWritten() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        let manifestURL = store.packageURL(for: editor.manifest.id).appending(path: "manifest.json")
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing())
        editor.saveNow()
        #expect(editor.lastError != nil)

        try FileManager.default.removeItem(at: manifestURL)
        editor.saveNow()

        #expect(editor.lastError == nil)
        #expect(try store.loadManifest(id: editor.manifest.id).id == editor.manifest.id)
        #expect(try store.loadDrawing(pageID: editor.pages[0].id, notebookID: editor.manifest.id).strokes.count == 1)
    }
}
