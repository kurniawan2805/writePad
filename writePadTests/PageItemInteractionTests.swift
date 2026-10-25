import Testing
import UIKit
@testable import writePad

@MainActor
struct PageItemInteractionTests {
    @Test func overlayPassesEmptyPaperAndWritingModeThroughToCanvas() throws {
        let store = NotebookStore(rootURL: .temporaryDirectory.appending(path: UUID().uuidString))
        let editor = try EditorViewModel.openDefault(store: store)
        let id = editor.pages[0].id
        editor.addText("Hit testing", to: id)
        let overlay = PageItemsOverlay(frame: CGRect(origin: .zero, size: PageLayout.pageSize))
        overlay.configure(viewModel: editor, pages: [(id, overlay.bounds)])
        #expect(overlay.hitTest(CGPoint(x: 60, y: 110), with: nil) is PageItemView)
        #expect(overlay.hitTest(CGPoint(x: 500, y: 500), with: nil) == nil)
        editor.isEditingItems = false
        overlay.configure(viewModel: editor, pages: [(id, overlay.bounds)])
        #expect(overlay.hitTest(CGPoint(x: 60, y: 110), with: nil) == nil)
        editor.isEditingItems = true
        editor.itemUndoManager.undo()
        overlay.configure(viewModel: editor, pages: [(id, overlay.bounds)])
        #expect(overlay.subviews.isEmpty)
    }

    @Test func imageOverlayRendersInItsPageFrameAndDeletionNeedsConfirmation() throws {
        let store = NotebookStore(rootURL: .temporaryDirectory.appending(path: UUID().uuidString))
        let editor = try EditorViewModel.openDefault(store: store)
        let id = editor.pages[0].id
        try editor.addImage(PageItemTests.imageData(), to: id)
        let overlay = PageItemsOverlay(frame: CGRect(origin: .zero, size: PageLayout.pageSize))
        overlay.configure(viewModel: editor, pages: [(id, overlay.bounds)])
        let imageView = try #require(overlay.subviews.first as? PageItemView)
        #expect(imageView.frame == editor.selectedItem?.frame)
        imageView.layer.displayIfNeeded()
        let rendered = UIGraphicsImageRenderer(size: imageView.bounds.size).image { context in
            imageView.layer.render(in: context.cgContext)
        }
        let image = try #require(rendered.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #expect(pixel[0] > 200 && pixel[1] < 50 && pixel[2] < 50)
        #expect(imageView.accessibilityLabel == "Page Image")
        #expect(editor.pageHasContent(at: 0))
        editor.deleteSelectedItem()
        #expect(!editor.pageHasContent(at: 0))
    }

    @Test func backupManifestKeepsItsOwnItemRevisionAfterNewSave() throws {
        let store = NotebookStore(rootURL: .temporaryDirectory.appending(path: UUID().uuidString))
        let editor = try EditorViewModel.openDefault(store: store)
        let id = editor.pages[0].id
        editor.addText("Original", to: id)
        editor.saveNow()
        let original = editor.pageItems[id]
        editor.addText("Newer", to: id)
        editor.saveNow()
        let manifestURL = store.packageURL(for: editor.manifest.id).appending(path: "manifest.json")
        try Data("broken".utf8).write(to: manifestURL, options: .atomic)
        let recovered = try store.loadManifestReport(id: editor.manifest.id)
        let reopened = try EditorViewModel(store: store, manifest: recovered.manifest)
        #expect(reopened.pageItems[id] == original)
        #expect(!recovered.notices.isEmpty)
    }

    @Test func orphanPageRecoveryAlsoRestoresItsTextAndImage() throws {
        let store = NotebookStore(rootURL: .temporaryDirectory.appending(path: UUID().uuidString))
        let editor = try EditorViewModel.openDefault(store: store)
        let manifestURL = store.packageURL(for: editor.manifest.id).appending(path: "manifest.json")
        let beforeInsertion = try Data(contentsOf: manifestURL)
        editor.addPage()
        let id = editor.pages[1].id
        editor.addText("Recovered text", to: id)
        try editor.addImage(PageItemTests.imageData(), to: id)
        editor.saveNow()
        #expect(editor.lastError == nil)
        // Model a process stopping after item/ink writes but before replacing the manifest.
        try beforeInsertion.write(to: manifestURL, options: .atomic)
        let load = try store.loadManifestReport(id: editor.manifest.id)
        #expect(load.needsSave)
        let reopened = try EditorViewModel(store: store, manifest: load.manifest, needsSave: load.needsSave)
        #expect(reopened.pages.map(\.id).contains(id))
        #expect(reopened.pageItems[id] == editor.pageItems[id])
        #expect(reopened.imageAssets.count == 1)
        reopened.saveNow()
        #expect(reopened.lastError == nil)
    }

    @Test func futureManifestRefusesAssetAndItemWrites() throws {
        let store = NotebookStore(rootURL: .temporaryDirectory.appending(path: UUID().uuidString))
        var manifest = try store.createNotebook(title: "Future")
        manifest.version = NotebookManifest.currentVersion + 1
        try store.saveManifest(manifest)
        let assetID = UUID()
        let snapshot = NotebookStore.SaveSnapshot(manifest: manifest, imageAssets: [assetID: PageItemTests.imageData()])
        #expect(throws: NotebookStore.StoreError.self) { try store.write(snapshot) }
        #expect(!FileManager.default.fileExists(atPath: store.imageURL(assetID: assetID, notebookID: manifest.id).path))
    }
}
