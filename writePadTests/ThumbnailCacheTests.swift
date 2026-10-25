import Foundation
import PDFKit
import Testing
import UIKit
@testable import writePad

extension LibraryViewModelTests {
    @Test func freshDiskThumbnailIsReusedAcrossLibraryRefresh() async throws {
        try library.createNotebook(title: "Cached", background: .grid)
        let notebook = try #require(library.notebooks.first)
        await library.loadThumbnail(for: notebook)
        let cacheURL = store.packageURL(for: notebook.id).appending(path: "thumb.png")
        let original = try Data(contentsOf: cacheURL)
        let stamp = try cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let manifestURL = store.packageURL(for: notebook.id).appending(path: "manifest.json")
        let manifestStamp = try #require(manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        #expect(try #require(stamp) > manifestStamp)
        try library.refresh()
        await library.loadThumbnail(for: notebook)
        #expect(try thumbnailPixels(#require(library.thumbnails[notebook.id])) == thumbnailPixels(#require(UIImage(data: original))))
        #expect(try Data(contentsOf: cacheURL) == original)
        #expect(try cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == stamp)
    }

    @Test func staleAndCorruptDiskThumbnailsAreRegenerated() async throws {
        try library.createNotebook(title: "Stale", background: .lined)
        let notebook = try #require(library.notebooks.first)
        await library.loadThumbnail(for: notebook)
        let cacheURL = store.packageURL(for: notebook.id).appending(path: "thumb.png")
        let original = try Data(contentsOf: cacheURL)
        var manifest = try store.loadManifest(id: notebook.id)
        manifest.pages[0].background = .grid
        try store.saveManifest(manifest)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: cacheURL.path)
        try library.refresh()
        await library.loadThumbnail(for: notebook)
        let updated = try Data(contentsOf: cacheURL)
        #expect(updated != original)
        try Data("broken PNG".utf8).write(to: cacheURL, options: .atomic)
        try library.refresh()
        await library.loadThumbnail(for: notebook)
        #expect(try Data(contentsOf: cacheURL) == updated)
        #expect(library.lastError == nil)
    }

    @Test func successfulSaveRefreshesFirstPageDiskThumbnail() async throws {
        try library.createNotebook(title: "Saved", background: .blank)
        let notebook = try #require(library.notebooks.first)
        await library.loadThumbnail(for: notebook)
        let cacheURL = store.packageURL(for: notebook.id).appending(path: "thumb.png")
        let blank = try Data(contentsOf: cacheURL)
        try library.openNotebook(notebook)
        let editor = try #require(library.editor)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing())
        editor.saveNow()
        #expect(editor.lastError == nil)
        #expect(try Data(contentsOf: cacheURL) != blank)
        editor.addPage()
        editor.setBackground(.grid, forPageAt: 1)
        editor.movePages(from: IndexSet(integer: 1), to: 0)
        editor.saveNow()
        let manifest = try store.loadManifest(id: notebook.id)
        #expect(manifest.pages.first?.background == .grid)
        try library.closeNotebook()
        await library.loadThumbnail(for: notebook)
        let expected = PageBackgroundRenderer.thumbnail(background: .grid, drawing: .init(), width: 180)
        let actualPixels = try thumbnailPixels(#require(library.thumbnails[notebook.id]))
        let expectedPixels = try thumbnailPixels(expected)
        #expect(actualPixels.count == expectedPixels.count)
        #expect(actualPixels == expectedPixels)
    }

    @Test func pdfCacheIncludesMarkupsAndKeepsSourceUntouched() async throws {
        let sourceURL = store.rootURL.appending(path: "Annotated.pdf")
        let source = PDFFixture.data(pageCount: 1)
        try source.write(to: sourceURL)
        try library.importPDF(from: sourceURL)
        let notebook = try #require(library.notebooks.first)
        let manifest = try store.loadManifest(id: notebook.id)
        let pageID = manifest.pages[0].id
        let markup = PDFMarkup(pageID: pageID, kind: .highlight,
                               bounds: CGRect(x: 20, y: 100, width: 200, height: 40), text: "Cached")
        try store.savePDFMarkups([markup], notebookID: notebook.id)
        await library.loadThumbnail(for: notebook)
        let document = try #require(PDFDocument(url: store.sourcePDFURL(for: notebook.id)))
        let page = try #require(document.page(at: 0))
        let expected = withExtendedLifetime(document) {
            page.addAnnotation(markup.annotation())
            return PageBackgroundRenderer.thumbnail(pdfPage: page, drawing: .init(), width: 180)
        }
        let actualPixels = try thumbnailPixels(#require(library.thumbnails[notebook.id]))
        let expectedPixels = try thumbnailPixels(expected)
        #expect(actualPixels.count == expectedPixels.count)
        #expect(actualPixels == expectedPixels)
        #expect(try Data(contentsOf: store.sourcePDFURL(for: notebook.id)) == source)
        let cacheURL = store.packageURL(for: notebook.id).appending(path: "thumb.png")
        #expect(UIImage(data: try Data(contentsOf: cacheURL)) != nil)
    }

    @Test func thumbnailWriteFailureDoesNotFailInkSave() throws {
        try library.createNotebook(title: "No cache", background: .blank)
        let notebook = try #require(library.notebooks.first)
        let cacheURL = store.packageURL(for: notebook.id).appending(path: "thumb.png")
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: false)
        try library.openNotebook(notebook)
        let editor = try #require(library.editor)
        editor.drawingDidChange(NotebookStoreTests.sampleDrawing())
        editor.saveNow()
        #expect(editor.lastError == nil)
        #expect(try store.loadDrawing(pageID: editor.pages[0].id, notebookID: notebook.id).strokes.count == 1)
    }

    @Test func newerFormatThumbnailRendersWithoutWritingCache() async throws {
        try library.createNotebook(title: "Future", background: .lined)
        let notebook = try #require(library.notebooks.first)
        var manifest = try store.loadManifest(id: notebook.id)
        manifest.version = NotebookManifest.currentVersion + 1
        try store.saveManifest(manifest)
        await library.loadThumbnail(for: notebook)
        #expect(library.thumbnails[notebook.id] != nil)
        #expect(!FileManager.default.fileExists(atPath: store.packageURL(for: notebook.id).appending(path: "thumb.png").path))
    }

    private func thumbnailPixels(_ image: UIImage) throws -> Data {
        // Normalize renderer-backed and PNG-backed images before sampling pixels.
        let encoded = try #require(image.pngData())
        let cgImage = try #require(UIImage(data: encoded)?.cgImage)
        var pixels = Data(count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: cgImage.width, height: cgImage.height,
                                                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return pixels
    }

}
