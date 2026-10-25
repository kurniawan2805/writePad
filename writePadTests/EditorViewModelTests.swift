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

    @Test func damagedPageDrawingStillOpensWithANotice() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing())
        editor.saveNow()
        let pageID = editor.pages[0].id
        let file = store.packageURL(for: editor.manifest.id).appending(path: "pages/\(pageID.uuidString).drawing")
        try Data("damaged".utf8).write(to: file)

        let reopened = try EditorViewModel.openDefault(store: store)

        #expect(reopened.drawing(forPage: pageID).strokes.isEmpty)
        #expect(reopened.recoveryNotice != nil)
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path(percentEncoded: false)))
        reopened.dismissRecoveryNotice()
        #expect(reopened.recoveryNotice == nil)
    }

    @Test func pageLeftByACrashedSaveReturnsAndIsSavedIntoTheManifest() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.saveNow()
        // A crash after the drawing was written but before the manifest was: the drawing is on disk, the page isn't listed.
        let pageID = UUID()
        let file = store.packageURL(for: editor.manifest.id).appending(path: "pages/\(pageID.uuidString).drawing")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try NotebookStoreTests.sampleDrawing().dataRepresentation().write(to: file)
        let written = Date.now.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: file.path(percentEncoded: false))

        let reopened = try EditorViewModel.openDefault(store: store)

        #expect(reopened.pages.count == 2)
        #expect(reopened.drawing(forPage: pageID).strokes.count == 1)
        #expect(reopened.recoveryNotice != nil)
        reopened.saveNow()
        #expect(try store.loadManifest(id: reopened.manifest.id).pages.map(\.id).contains(pageID))
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
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

        editor.deletePage(at: 1)
        let reopened = try reopen(editor)
        #expect(reopened.pages.map(\.id) == [editor.pages[0].id])
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
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
