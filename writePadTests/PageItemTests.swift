import PDFKit
import PencilKit
import Testing
import UIKit
@testable import writePad

@MainActor
struct PageItemTests {
    let store: NotebookStore
    let editor: EditorViewModel

    init() throws {
        store = NotebookStore(rootURL: .temporaryDirectory.appending(path: UUID().uuidString))
        editor = try EditorViewModel.openDefault(store: store)
    }

    private var pageID: UUID { editor.pages[0].id }

    static func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
    }

    @Test func v4LoadsAndUpgradesOnlyOnEdit() throws {
        var old = editor.manifest
        old.version = 4
        try store.saveManifest(old)
        let loaded = try EditorViewModel(store: store, manifest: store.loadManifest(id: old.id))
        #expect(loaded.pageItems[pageID] == [])
        #expect(loaded.manifest.version == 4)
        loaded.addText("Older notebook", to: pageID)
        loaded.saveNow()
        #expect(loaded.lastError == nil)
        #expect(try store.loadManifest(id: old.id).version == 5)
    }

    @Test func textAndImageRoundTripKeepInkAndSeparateAssets() throws {
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing(), pageID: pageID)
        editor.addText("Hello v5", to: pageID)
        try editor.addImage(Self.imageData(), to: pageID)
        let expected = editor.pageItems[pageID]
        editor.saveNow()
        #expect(editor.lastError == nil)
        let manifest = try store.loadManifest(id: editor.manifest.id)
        let reopened = try EditorViewModel(store: store, manifest: manifest)
        #expect(reopened.pageItems[pageID] == expected)
        #expect(reopened.drawing(forPage: pageID).strokes.count == 1)
        let assetID = try #require(reopened.imageAssets.keys.first)
        #expect(try Data(contentsOf: store.imageURL(assetID: assetID, notebookID: manifest.id)) == reopened.imageAssets[assetID])
        #expect(manifest.pages[0].itemsRevision != nil)
    }

    @Test func undoRedoTextMoveResizeAndDeletion() throws {
        editor.addText("Original", to: pageID)
        let original = try #require(editor.selectedItem)
        var edited = original
        edited.frame = CGRect(x: 200, y: 300, width: 320, height: 180)
        edited.content = .text("Edited", fontSize: 36)
        editor.updateItem(edited, on: pageID)
        editor.itemUndoManager.undo()
        #expect(editor.selectedItem == original)
        editor.itemUndoManager.redo()
        #expect(editor.selectedItem == edited)
        editor.deleteSelectedItem()
        #expect(editor.pageItems[pageID] == [])
        editor.itemUndoManager.undo()
        #expect(editor.pageItems[pageID] == [edited])
        editor.itemUndoManager.undo()
        editor.itemUndoManager.undo()
        #expect(editor.pageItems[pageID] == [])
        editor.itemUndoManager.redo()
        #expect(editor.pageItems[pageID] == [original])
    }

    @Test func frameClampingAndInvalidImageDoNotLoseItems() throws {
        editor.addText(to: pageID)
        var item = try #require(editor.selectedItem)
        item.frame = CGRect(x: -100, y: 100_000, width: 100_000, height: -10)
        editor.updateItem(item, on: pageID)
        let frame = try #require(editor.selectedItem).frame
        #expect(frame.minX == 0)
        #expect(frame.maxY <= PageLayout.pageSize.height)
        #expect(frame.width == PageLayout.pageSize.width)
        #expect(frame.height == 32)
        #expect(throws: (any Error).self) { try editor.addImage(Data([1, 2, 3]), to: pageID) }
        #expect(editor.pageItems[pageID]?.count == 1)
        #expect(editor.imageAssets.isEmpty)
    }

    @Test func readOnlyRefusesEveryItemMutationAndAssetWrite() throws {
        editor.addText("Keep", to: pageID)
        editor.saveNow()
        let readonly = try EditorViewModel(store: store, manifest: editor.manifest, readOnly: true)
        readonly.selectedItemID = editor.selectedItemID
        let expected = readonly.pageItems
        readonly.addText("No", to: pageID)
        try readonly.addImage(Self.imageData(), to: pageID)
        readonly.deleteSelectedItem()
        readonly.setItems([], on: pageID)
        readonly.saveNow()
        #expect(readonly.pageItems == expected)
        #expect(readonly.imageAssets.isEmpty)
        #expect(!readonly.itemUndoManager.canUndo)
    }

    @Test func failedManifestWriteKeepsPreviousRevisionAndRetrySavesNewest() throws {
        editor.addText("Before", to: pageID)
        editor.saveNow()
        let old = editor.manifest
        let manifestURL = store.packageURL(for: old.id).appending(path: "manifest.json")
        let oldData = try Data(contentsOf: manifestURL)
        editor.addText("After", to: pageID)
        try editor.addImage(Self.imageData(), to: pageID)
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)
        editor.saveNow()
        #expect(editor.lastError != nil)
        #expect(try store.loadItems(page: old.pages[0], notebookID: old.id).count == 1)
        try FileManager.default.removeItem(at: manifestURL)
        try oldData.write(to: manifestURL, options: .atomic)
        editor.saveNow()
        #expect(editor.lastError == nil)
        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: old.id))
        #expect(reopened.pageItems[pageID] == editor.pageItems[pageID])
        #expect(reopened.imageAssets.count == 1)
    }

    @Test func autosaveThenFlushKeepsLatestItemRevision() async throws {
        editor.saveTiming = SaveTiming(delay: .milliseconds(1), maxLatency: .milliseconds(5))
        editor.addText("First", to: pageID)
        try await Task.sleep(for: .milliseconds(10))
        editor.addText("Latest", to: pageID)
        try editor.addImage(Self.imageData(), to: pageID)
        editor.saveNow()
        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: editor.manifest.id))
        #expect(reopened.pageItems[pageID] == editor.pageItems[pageID])
        #expect(reopened.imageAssets.count == 1)
    }

    @Test func reorderAndDeleteDoNotAttachItemsToWrongPage() throws {
        let firstID = pageID
        editor.addText("First page", to: firstID)
        editor.addPage()
        let secondID = editor.pages[1].id
        editor.addText("Second page", to: secondID)
        editor.movePages(from: [1], to: 0)
        #expect(editor.pages[0].id == secondID)
        #expect(!editor.itemUndoManager.canUndo)
        editor.deletePage(at: 1)
        editor.saveNow()
        let reopened = try EditorViewModel(store: store, manifest: store.loadManifest(id: editor.manifest.id))
        #expect(reopened.pages.map(\.id) == [secondID])
        #expect(reopened.pageItems[firstID] == nil)
        #expect(reopened.pageItems[secondID]?.count == 1)
    }

    @Test func damagedOrMissingItemDocumentStopsOpenAndKeepsBytes() throws {
        editor.addText("Valuable", to: pageID)
        editor.saveNow()
        let manifest = editor.manifest
        let revision = try #require(manifest.pages[0].itemsRevision)
        let url = store.itemsURL(pageID: pageID, revision: revision, notebookID: manifest.id)
        let damage = Data("broken item document".utf8)
        try damage.write(to: url, options: .atomic)
        #expect(throws: (any Error).self) { try EditorViewModel(store: store, manifest: manifest) }
        #expect(try Data(contentsOf: url) == damage)
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try EditorViewModel(store: store, manifest: manifest) }
    }

    @Test func damagedOrMissingImageStopsOpenAndKeepsBytes() throws {
        try editor.addImage(Self.imageData(), to: pageID)
        editor.saveNow()
        let id = try #require(editor.imageAssets.keys.first)
        let url = store.imageURL(assetID: id, notebookID: editor.manifest.id)
        let damage = Data("broken image".utf8)
        try damage.write(to: url, options: .atomic)
        #expect(throws: (any Error).self) { try EditorViewModel(store: store, manifest: editor.manifest) }
        #expect(try Data(contentsOf: url) == damage)
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try EditorViewModel(store: store, manifest: editor.manifest) }
    }
}
