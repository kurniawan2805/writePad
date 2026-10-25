import PDFKit
import PencilKit
import UIKit

/// What one thumbnail needs, copied so it can be rendered off the main actor.
struct PageThumbnailJob: Sendable {
    private static let renderQueue = DispatchQueue(label: "writePad.thumbnails", qos: .utility)

    let id: UUID
    let version: Int
    let background: PageBackground
    let pdfPageIndex: Int?
    let drawing: PKDrawing
    let markups: [PDFMarkup]
    var items: [PageItem] = []
    var imageAssets: [UUID: Data] = [:]

    /// UIKit/PencilKit rendering can block; keep it off Swift's cooperative executor so saves can still resume.
    static func images(for jobs: [Self], sourceURL: URL, width: CGFloat) -> AsyncStream<(Self, UIImage)> {
        AsyncStream { continuation in
            renderQueue.async {
                let document = jobs.contains { $0.pdfPageIndex != nil } ? PDFDocument(url: sourceURL) : nil
                for job in jobs {
                    let image = autoreleasepool { job.render(document: document, width: width) }
                    continuation.yield((job, image))
                }
                continuation.finish()
            }
        }
    }

    static func libraryImage(store: NotebookStore, notebookID: UUID) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                continuation.resume(with: Result { try cachedLibraryImage(store: store, notebookID: notebookID) })
            }
        }
    }

    /// Called on the save queue; a cache failure must never turn a successful ink save into a failure.
    static func refreshLibraryCache(store: NotebookStore, notebookID: UUID) {
        renderQueue.sync {
            _ = try? cachedLibraryImage(store: store, notebookID: notebookID, force: true)
        }
    }

    private static func cachedLibraryImage(store: NotebookStore, notebookID: UUID, force: Bool = false) throws -> UIImage? {
        let package = store.packageURL(for: notebookID)
        let manifestURL = package.appending(path: "manifest.json")
        let cacheURL = package.appending(path: "thumb.png")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifestDate = try manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if !force, let manifestDate,
           let cacheDate = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           cacheDate > manifestDate, let data = try? Data(contentsOf: cacheURL), let image = UIImage(data: data) {
            return image
        }
        let manifest = try store.loadManifest(id: notebookID)
        guard let page = manifest.pages.first else { return nil }
        let drawing = try store.loadDrawing(pageID: page.id, notebookID: notebookID)
        let markups = try store.loadPDFMarkups(notebookID: notebookID).filter { $0.pageID == page.id }
        let document = page.pdfPageIndex == nil ? nil : PDFDocument(url: store.sourcePDFURL(for: notebookID))
        if let index = page.pdfPageIndex, document?.page(at: index) == nil { throw NotebookStore.StoreError.invalidPDF }
        var job = Self(id: page.id, version: 0, background: page.background, pdfPageIndex: page.pdfPageIndex,
                       drawing: drawing, markups: markups, items: try store.loadItems(page: page, notebookID: notebookID))
        for item in job.items {
            if case let .image(id) = item.content { job.imageAssets[id] = try store.loadImage(assetID: id, notebookID: notebookID) }
        }
        let image = autoreleasepool { job.render(document: document, width: 180) }
        // Never publish an older render as fresh after a concurrent save. Newer formats remain untouched.
        if !manifest.isNewerThanSupported, let data = image.pngData(),
           (try? Data(contentsOf: manifestURL)) == manifestData {
            do {
                try data.write(to: cacheURL, options: .atomic)
                if let manifestDate {
                    // Tie freshness to this manifest, allowing for filesystem timestamp rounding.
                    let stamp = manifestDate.addingTimeInterval(0.000_001)
                    try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: cacheURL.path)
                }
            } catch {
                // Disposable cache: the rendered image still works for this session.
            }
        }
        return image
    }

    /// PDF pages come from a private copy of the document: the one on screen belongs to the PDF view.
    func render(document: PDFDocument?, width: CGFloat) -> UIImage {
        withExtendedLifetime(document) {
            if let pdfPageIndex, let page = document?.page(at: pdfPageIndex) {
                for markup in markups { page.addAnnotation(markup.annotation()) }
                let base = PageBackgroundRenderer.thumbnail(pdfPage: page, drawing: drawing, width: width)
                return withItems(on: base, size: PDFPageCanvas.displaySize(for: page))
            }
            let base = PageBackgroundRenderer.thumbnail(background: background, drawing: drawing, width: width)
            return withItems(on: base, size: PageLayout.pageSize)
        }
    }

    private func withItems(on base: UIImage, size: CGSize) -> UIImage {
        guard !items.isEmpty else { return base }
        return UIGraphicsImageRenderer(size: base.size).image { renderer in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            renderer.cgContext.scaleBy(x: base.size.width / size.width, y: base.size.height / size.height)
            PageItemRenderer.draw(items, assets: imageAssets, in: renderer.cgContext)
        }
    }
}
