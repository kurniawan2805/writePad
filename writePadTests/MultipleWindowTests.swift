import Foundation
import SwiftData
import Testing
@testable import writePad

@MainActor
struct MultipleWindowTests {
    let store: NotebookStore
    let container: ModelContainer
    let left: LibraryViewModel
    let right: LibraryViewModel

    init() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
        container = try ModelContainer(for: LibraryNotebook.self, LibraryFolder.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        left = LibraryViewModel(container: container, store: store)
        right = LibraryViewModel(container: container, store: store)
    }

    @Test func secondWindowOpensReadOnlyAfterFlushingLatestInk() throws {
        let manifest = try store.createNotebook(title: "Shared")
        defer { left.disconnect(); right.disconnect() }
        try left.openNotebook(id: manifest.id)
        let writer = try #require(left.editor)
        writer.drawingDidChange(NotebookStoreTests.sampleDrawing())
        try right.openNotebook(id: manifest.id)
        let reader = try #require(right.editor)
        #expect(!writer.isReadOnly)
        #expect(reader.isReadOnly)
        #expect(reader.drawing(forPage: manifest.pages[0].id).strokes.count == 1)
        let before = try Data(contentsOf: store.packageURL(for: manifest.id).appending(path: "manifest.json"))
        reader.addPage()
        reader.deletePage(at: 0)
        reader.drawingDidChange(.init())
        reader.saveNow()
        #expect(reader.pages.count == 1)
        #expect(try Data(contentsOf: store.packageURL(for: manifest.id).appending(path: "manifest.json")) == before)
        #expect(try store.loadDrawing(pageID: manifest.pages[0].id, notebookID: manifest.id).strokes.count == 1)
    }

    @Test func differentNotebooksHaveIndependentWritersAndLibraryState() throws {
        let first = try store.createNotebook(title: "One")
        let second = try store.createNotebook(title: "Two")
        defer { left.disconnect(); right.disconnect() }
        try left.refresh()
        try right.refresh()
        left.searchText = "One"
        #expect(right.searchText.isEmpty)
        try left.openNotebook(id: first.id)
        try right.openNotebook(id: second.id)
        #expect(left.editor?.isReadOnly == false)
        #expect(right.editor?.isReadOnly == false)
        left.editor?.addPage()
        right.editor?.addPage()
        try left.closeNotebook()
        try right.closeNotebook()
        #expect(try store.loadManifest(id: first.id).pages.count == 2)
        #expect(try store.loadManifest(id: second.id).pages.count == 2)
    }

    @Test func closingReaderDoesNotReleaseWriterAndReopenAcquiresAfterWriterCloses() throws {
        let manifest = try store.createNotebook(title: "Ownership")
        defer { left.disconnect(); right.disconnect() }
        try left.openNotebook(id: manifest.id)
        try right.openNotebook(id: manifest.id)
        try right.closeNotebook()
        try right.openNotebook(id: manifest.id)
        #expect(right.editor?.isReadOnly == true)
        try left.closeNotebook()
        #expect(right.editor?.isReadOnly == true)
        try right.closeNotebook()
        try right.openNotebook(id: manifest.id)
        #expect(right.editor?.isReadOnly == false)
    }

    @Test func crossWindowRenameAndDeleteCannotRaceWriter() throws {
        try left.createNotebook(title: "Protected", background: .blank)
        try right.refresh()
        let record = try #require(right.notebooks.first)
        defer { left.disconnect(); right.disconnect() }
        try left.openNotebook(id: record.id)
        left.editor?.addPage()
        #expect(throws: (any Error).self) { try right.renameNotebook(record, title: "Lost rename") }
        #expect(throws: (any Error).self) { try right.deleteNotebook(record) }
        try left.closeNotebook()
        try right.renameNotebook(record, title: "Allowed")
        #expect(try store.loadManifest(id: record.id).title == "Allowed")
        try right.deleteNotebook(record)
        #expect(try store.listNotebooks().isEmpty)
    }

    @Test func loadFailureDoesNotLeaveAWriteLock() throws {
        let manifest = try store.createNotebook(title: "Damaged items")
        var damaged = manifest
        damaged.pages[0].itemsRevision = UUID()
        try store.saveManifest(damaged)
        #expect(throws: (any Error).self) { try left.openNotebook(id: manifest.id) }
        try store.saveManifest(manifest)
        defer { right.disconnect() }
        try right.openNotebook(id: manifest.id)
        #expect(right.editor?.isReadOnly == false)
    }

    @Test func failedCloseRetainsWriterAndDisconnectRetainsUnsavedInkUntilRetry() throws {
        let manifest = try store.createNotebook(title: "Full disk")
        try left.openNotebook(id: manifest.id)
        let writer = try #require(left.editor)
        writer.drawingDidChange(NotebookStoreTests.sampleDrawing())
        let file = store.packageURL(for: manifest.id).appending(path: "manifest.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try left.closeNotebook()
        #expect(left.editor === writer)
        #expect(writer.lastError != nil)
        #expect(throws: (any Error).self) { try right.openNotebook(id: manifest.id) }
        left.disconnect()
        #expect(left.editor == nil)
        #expect(throws: (any Error).self) { try right.openNotebook(id: manifest.id) }
        try FileManager.default.removeItem(at: file)
        defer { right.disconnect() }
        try right.openNotebook(id: manifest.id)
        #expect(right.editor?.isReadOnly == false)
        #expect(right.editor?.drawing(forPage: manifest.pages[0].id).strokes.count == 1)
    }

    @Test func readOnlyOpenNeverQuarantinesWritersDamagedInk() throws {
        let manifest = try store.createNotebook(title: "Keep damaged bytes")
        defer { left.disconnect(); right.disconnect() }
        try left.openNotebook(id: manifest.id)
        let file = store.packageURL(for: manifest.id).appending(path: "pages/\(manifest.pages[0].id).drawing")
        let damaged = Data("damaged".utf8)
        try damaged.write(to: file, options: .atomic)
        #expect(throws: (any Error).self) { try right.openNotebook(id: manifest.id) }
        #expect(try Data(contentsOf: file) == damaged)
        #expect(!FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path))
    }

    @Test func sceneContextsRefreshFolderMetadataFromOtherWindows() throws {
        try left.createFolder(title: "Before")
        try right.refresh()
        #expect(right.folders.first?.title == "Before")
        try left.renameFolder(#require(left.folders.first), title: "After")
        try right.refresh()
        #expect(right.folders.first?.title == "After")
        try left.deleteFolder(#require(left.folders.first))
        try right.refresh()
        #expect(right.folders.isEmpty)
    }

    @Test func callbacksFromAClosedCanvasCannotWriteAfterOwnershipTransfers() throws {
        let manifest = try store.createNotebook(title: "Late callbacks")
        defer { left.disconnect(); right.disconnect() }
        try left.openNotebook(id: manifest.id)
        let old = try #require(left.editor)
        try left.closeNotebook()
        #expect(old.isClosed)
        try right.openNotebook(id: manifest.id)
        old.drawingDidChange(NotebookStoreTests.sampleDrawing())
        old.addPage()
        old.saveNow()
        #expect(old.pages.count == 1)
        #expect(old.drawing(forPage: manifest.pages[0].id).strokes.isEmpty)
        #expect(try store.loadDrawing(pageID: manifest.pages[0].id, notebookID: manifest.id).strokes.isEmpty)
        #expect(right.editor?.isReadOnly == false)
    }

    @Test func windowRequestsDistinguishTwoCopiesOfTheSameNotebook() throws {
        let id = UUID()
        let first = NotebookWindowRequest(notebookID: id)
        let second = NotebookWindowRequest(notebookID: id)
        #expect(first != second)
        #expect(try JSONDecoder().decode(NotebookWindowRequest.self, from: JSONEncoder().encode(first)) == first)
    }
}
