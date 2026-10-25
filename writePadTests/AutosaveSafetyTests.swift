import Foundation
import PencilKit
import Testing
@testable import writePad

@MainActor
struct AutosaveSafetyTests {
    @Test func failedManifestSaveDoesNotDeletePersistedInk() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = NotebookStore(rootURL: root)
        let editor = try EditorViewModel.openDefault(store: store)
        editor.addPage()
        let pageID = editor.pages[1].id
        editor.drawingDidChange(PageLayout(pageCount: 2).merge([PKDrawing(), NotebookStoreTests.sampleDrawing()]))
        editor.saveNow()
        let manifestURL = store.packageURL(for: editor.manifest.id).appending(path: "manifest.json")
        let savedManifest = try Data(contentsOf: manifestURL)
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)

        editor.deletePage(at: 1)
        editor.saveNow()

        #expect(editor.lastError != nil)
        #expect(try store.loadDrawing(pageID: pageID, notebookID: editor.manifest.id).strokes.count == 1)
        try FileManager.default.removeItem(at: manifestURL)
        try savedManifest.write(to: manifestURL, options: .atomic)
        #expect(try store.loadManifest(id: editor.manifest.id).pages.count == 2)
        editor.saveNow()
        #expect(editor.lastError == nil)
        #expect(try store.loadManifest(id: editor.manifest.id).pages.count == 1)
        #expect(try store.loadDrawing(pageID: pageID, notebookID: editor.manifest.id).strokes.isEmpty)
    }
}
