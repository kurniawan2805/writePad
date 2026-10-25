import Foundation
import SwiftData
import Testing
import UIKit
@testable import writePad

@MainActor
struct LibraryViewModelTests {
    let store: NotebookStore
    let container: ModelContainer
    let library: LibraryViewModel

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
        container = try ModelContainer(for: LibraryNotebook.self, LibraryFolder.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        library = LibraryViewModel(container: container, store: store)
    }

    @Test func existingPackagesAreIndexedWithoutChangingInk() throws {
        let manifest = try store.createNotebook(title: "Before Library")
        try store.saveDrawing(NotebookStoreTests.sampleDrawing(), pageID: manifest.pages[0].id, notebookID: manifest.id)

        try library.refresh()
        try library.refresh()

        #expect(library.notebooks.map(\.id) == [manifest.id])
        let drawing = try store.loadDrawing(pageID: manifest.pages[0].id, notebookID: manifest.id)
        #expect(drawing.strokes.count == 1)
    }

    @Test func createsNotebookWithChosenPaperInSelectedFolder() throws {
        try library.createFolder(title: "School")
        let folder = try #require(library.folders.first)
        library.selectedFolderID = folder.id

        try library.createNotebook(title: "  Physics  ", background: .grid)

        let notebook = try #require(library.visibleNotebooks.first)
        let manifest = try store.loadManifest(id: notebook.id)
        #expect(manifest.title == "Physics")
        #expect(manifest.pages.first?.background == .grid)
        #expect(notebook.folderID == folder.id)
    }

    @Test func importingPDFAddsItToTheSelectedFolder() throws {
        let sourceURL = store.rootURL.appending(path: "Course Notes.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.pdfData { context in
            context.beginPage()
        }.write(to: sourceURL)
        try library.createFolder(title: "Courses")
        let folder = try #require(library.folders.first)
        library.selectedFolderID = folder.id

        try library.importPDF(from: sourceURL)

        let notebook = try #require(library.visibleNotebooks.first)
        let manifest = try store.loadManifest(id: notebook.id)
        #expect(notebook.title == "Course Notes")
        #expect(notebook.folderID == folder.id)
        #expect(manifest.pages.map(\.pdfPageIndex) == [0])
        #expect(FileManager.default.fileExists(atPath: store.sourcePDFURL(for: notebook.id).path(percentEncoded: false)))
    }

    @Test func titleSearchCombinesWithFolderFilter() throws {
        try library.createNotebook(title: "Physics", background: .blank)
        try library.createFolder(title: "School")
        library.selectedFolderID = library.folders.first?.id
        try library.createNotebook(title: "PHYSICS Lab", background: .lined)
        try library.createNotebook(title: "Math", background: .blank)

        library.searchText = "physics"
        #expect(library.visibleNotebooks.map(\.title) == ["PHYSICS Lab"])
        library.selectedFolderID = nil
        #expect(library.visibleNotebooks.count == 2)
    }

    @Test func sortsByEachDateAndNaturalTitle() throws {
        var first = try store.createNotebook(title: "Note 10")
        first.createdAt = Date(timeIntervalSince1970: 100)
        first.updatedAt = Date(timeIntervalSince1970: 300)
        try store.saveManifest(first)
        var second = try store.createNotebook(title: "Note 2")
        second.createdAt = Date(timeIntervalSince1970: 200)
        second.updatedAt = Date(timeIntervalSince1970: 200)
        try store.saveManifest(second)
        try library.refresh()

        library.sortOrder = .updated
        #expect(library.visibleNotebooks.map(\.id) == [first.id, second.id])
        library.sortOrder = .created
        #expect(library.visibleNotebooks.map(\.id) == [second.id, first.id])
        library.sortOrder = .name
        #expect(library.visibleNotebooks.map(\.id) == [second.id, first.id])
    }

    @Test func renameUpdatesPackageAndSearch() throws {
        try library.createNotebook(title: "Old", background: .blank)
        let notebook = try #require(library.notebooks.first)

        try library.renameNotebook(notebook, title: "New")
        library.searchText = "new"

        #expect(library.visibleNotebooks.map(\.title) == ["New"])
        #expect(try store.loadManifest(id: notebook.id).title == "New")
    }

    @Test func emptyNamesDoNotCreatePackagesOrFolders() throws {
        #expect(throws: (any Error).self) { try library.createNotebook(title: " \n", background: .blank) }
        #expect(throws: (any Error).self) { try library.createFolder(title: "  ") }
        #expect(try store.listNotebooks().isEmpty)
        #expect(library.folders.isEmpty)
    }

    @Test func movingAndDeletingFolderKeepsNotebookAndInk() throws {
        try library.createNotebook(title: "Keep", background: .dotted)
        try library.createFolder(title: "Remove")
        let notebook = try #require(library.notebooks.first)
        let folder = try #require(library.folders.first)
        let manifest = try store.loadManifest(id: notebook.id)
        try store.saveDrawing(NotebookStoreTests.sampleDrawing(), pageID: manifest.pages[0].id, notebookID: notebook.id)
        try library.moveNotebook(notebook, to: folder.id)
        library.selectedFolderID = folder.id

        try library.deleteFolder(folder)

        #expect(library.selectedFolderID == nil)
        #expect(library.folders.isEmpty)
        #expect(library.notebooks.first?.folderID == nil)
        #expect(try store.loadManifest(id: notebook.id).title == "Keep")
        #expect(try store.loadDrawing(pageID: manifest.pages[0].id, notebookID: notebook.id).strokes.count == 1)
    }

    @Test func deletingNotebookRemovesPackageAndIndex() throws {
        try library.createNotebook(title: "Delete", background: .blank)
        let notebook = try #require(library.notebooks.first)
        let id = notebook.id

        try library.deleteNotebook(notebook)

        #expect(!FileManager.default.fileExists(atPath: store.packageURL(for: id).path(percentEncoded: false)))
        #expect(library.notebooks.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<LibraryNotebook>()) == 0)
    }

    @Test func returningToLibraryFlushesInkAndRefreshesThumbnail() throws {
        try library.createNotebook(title: "Ink", background: .lined)
        let notebook = try #require(library.notebooks.first)
        try library.openNotebook(notebook)
        let editor = try #require(library.editor)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing())

        try library.closeNotebook()
        library.loadThumbnail(for: notebook)
        try library.openNotebook(notebook)

        #expect(library.thumbnails[notebook.id] != nil)
        #expect(library.editor?.drawing(forPage: editor.pages[0].id).strokes.count == 1)
    }

    @Test func folderMembershipSurvivesPersistentContainerReopen() throws {
        let databaseURL = store.rootURL.appending(path: "library.store")
        let configuration = ModelConfiguration(url: databaseURL)
        let persistent = try ModelContainer(for: LibraryNotebook.self, LibraryFolder.self, configurations: configuration)
        let original = LibraryViewModel(container: persistent, store: store)
        try original.createFolder(title: "School")
        let folder = try #require(original.folders.first)
        try original.renameFolder(folder, title: "Courses")
        original.selectedFolderID = folder.id
        try original.createNotebook(title: "Math", background: .grid)

        let reopenedContainer = try ModelContainer(for: LibraryNotebook.self, LibraryFolder.self, configurations: configuration)
        let reopened = LibraryViewModel(container: reopenedContainer, store: store)
        try reopened.refresh()

        #expect(reopened.folders.first?.title == "Courses")
        #expect(reopened.notebooks.first?.folderID == folder.id)
    }

    @Test func unreadableInkPreventsOpeningWithoutOverwritingFile() throws {
        try library.createNotebook(title: "Damaged", background: .blank)
        let notebook = try #require(library.notebooks.first)
        let manifest = try store.loadManifest(id: notebook.id)
        let file = store.packageURL(for: notebook.id).appending(path: "pages/\(manifest.pages[0].id).drawing")
        let original = Data([0xFF, 0xFF, 0xFF])
        try original.write(to: file, options: .atomic)

        #expect(throws: (any Error).self) { try library.openNotebook(notebook) }

        #expect(library.editor == nil)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func failedSaveKeepsEditorOpenUntilRetrySucceeds() throws {
        try library.createNotebook(title: "Retry", background: .blank)
        let notebook = try #require(library.notebooks.first)
        try library.openNotebook(notebook)
        let editor = try #require(library.editor)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing())
        let manifestURL = store.packageURL(for: notebook.id).appending(path: "manifest.json")
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)

        try library.closeNotebook()
        #expect(library.editor != nil)
        #expect(editor.lastError != nil)

        try FileManager.default.removeItem(at: manifestURL)
        try library.closeNotebook()
        #expect(library.editor == nil)
        #expect(try store.loadDrawing(pageID: editor.pages[0].id, notebookID: notebook.id).strokes.count == 1)
    }

    @Test func pdfNotebookThumbnailShowsThePDFPageInItsOwnShape() throws {
        let url = store.rootURL.appending(path: "Letter.pdf")
        try PDFFixture.data(pageCount: 1).write(to: url, options: .atomic)
        try library.importPDF(from: url)
        let notebook = try #require(library.notebooks.first)

        library.loadThumbnail(for: notebook)

        let thumbnail = try #require(library.thumbnails[notebook.id])
        let blankPaper = PageBackgroundRenderer.thumbnail(background: .blank, drawing: .init(), width: thumbnail.size.width)
        #expect(thumbnail.pngData() != blankPaper.pngData())
        #expect(abs(thumbnail.size.width / thumbnail.size.height - 612.0 / 792.0) < 0.01)
    }

    @Test func importsPDFWhoseFileNameHasSpaces() throws {
        let url = store.rootURL.appending(path: "Kuliah 1 - Fisika.pdf")
        try PDFFixture.data(pageCount: 1).write(to: url, options: .atomic)

        try library.importPDF(from: url)

        #expect(library.notebooks.map(\.title) == ["Kuliah 1 - Fisika"])
    }
}
