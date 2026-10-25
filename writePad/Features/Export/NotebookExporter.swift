import PDFKit
import PencilKit
import UIKit

struct NotebookExport: Sendable {
    let manifest: NotebookManifest
    let drawings: [UUID: Data]
    let sourcePDFURL: URL
    var markups: [PDFMarkup] = []
    var pageItems: [UUID: [PageItem]] = [:]
    var imageAssets: [UUID: Data] = [:]
}

enum NotebookExportFormat: Sendable {
    case pdf
    case png(pageID: UUID)
}

enum NotebookExporter {
    enum ExportError: LocalizedError {
        case noPages, missingPDF, missingPage, invalidPageSize

        var errorDescription: String? {
            switch self {
            case .noPages: "This notebook has no pages to export."
            case .missingPDF: "The original PDF couldn't be read. Your notebook hasn't been changed."
            case .missingPage: "This page is no longer available."
            case .invalidPageSize: "The PDF contains a page with an invalid size."
            }
        }
    }

    static func export(_ snapshot: NotebookExport, as format: NotebookExportFormat,
                       directory: URL = .temporaryDirectory) throws -> URL {
        guard !snapshot.manifest.pages.isEmpty else { throw ExportError.noPages }
        let pages: [PageInfo]
        let suffix: String
        switch format {
        case .pdf:
            pages = snapshot.manifest.pages
            suffix = ".pdf"
        case let .png(pageID):
            guard let index = snapshot.manifest.pages.firstIndex(where: { $0.id == pageID }) else { throw ExportError.missingPage }
            pages = [snapshot.manifest.pages[index]]
            suffix = " - Page \(index + 1).png"
        }
        let document: PDFDocument?
        if pages.contains(where: { $0.pdfPageIndex != nil }) {
            guard let pdf = PDFDocument(url: snapshot.sourcePDFURL), !pdf.isLocked else { throw ExportError.missingPDF }
            document = pdf
        } else {
            document = nil
        }
        for page in pages { _ = try pageSize(page, document: document) }
        let folder = directory.appending(path: "writePad-Export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let name = snapshot.manifest.title.components(separatedBy: .init(charactersIn: "/\\:\n\r"))
                .joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = folder.appending(path: String((name.isEmpty ? "Notebook" : name).prefix(100)) + suffix)
            switch format {
            case .pdf:
                try renderPDF(pages, snapshot: snapshot, document: document, to: url)
            case .png:
                try renderPNG(pages[0], snapshot: snapshot, document: document, to: url)
            }
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private static func renderPDF(_ pages: [PageInfo], snapshot: NotebookExport, document: PDFDocument?, to url: URL) throws {
        let staging = url.deletingLastPathComponent().appending(path: "export.partial")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: snapshot.manifest.title, kCGPDFContextCreator as String: "writePad"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PageLayout.pageSize), format: format)
        var renderError: Error?
        try renderer.writePDF(to: staging) { context in
            for page in pages {
                do {
                    try Task.checkCancellation()
                    try autoreleasepool {
                        let size = try pageSize(page, document: document)
                        context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                        try draw(page, snapshot: snapshot, document: document, size: size, in: context.cgContext, vectorInk: true)
                    }
                } catch {
                    renderError = error
                    break
                }
            }
        }
        if let renderError { throw renderError }
        try FileManager.default.moveItem(at: staging, to: url)
    }

    private static func renderPNG(_ page: PageInfo, snapshot: NotebookExport, document: PDFDocument?, to url: URL) throws {
        try Task.checkCancellation()
        let size = try pageSize(page, document: document)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2, 4096 / max(size.width, size.height))
        format.opaque = true
        format.preferredRange = .standard
        var renderError: Error?
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            do {
                try draw(page, snapshot: snapshot, document: document, size: size, in: context.cgContext)
            } catch {
                renderError = error
            }
        }
        if let renderError { throw renderError }
        try data.write(to: url, options: .atomic)
    }

    private static func pageSize(_ page: PageInfo, document: PDFDocument?) throws -> CGSize {
        guard let index = page.pdfPageIndex else { return PageLayout.pageSize }
        guard let source = document?.page(at: index) else { throw ExportError.missingPage }
        let bounds = source.bounds(for: .cropBox)
        let size = source.rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { throw ExportError.invalidPageSize }
        return size
    }

    private static func draw(_ page: PageInfo, snapshot: NotebookExport, document: PDFDocument?,
                             size: CGSize, in context: CGContext, vectorInk: Bool = false) throws {
        let rect = CGRect(origin: .zero, size: size)
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
        if let index = page.pdfPageIndex, let source = document?.page(at: index) {
            let annotations = snapshot.markups.filter { $0.pageID == page.id }.map { $0.annotation() }
            for annotation in annotations { source.addAnnotation(annotation) }
            defer { for annotation in annotations { source.removeAnnotation(annotation) } }
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            source.draw(with: .cropBox, to: context)
            context.restoreGState()
        } else {
            context.addPath(PageBackgroundRenderer.patternPath(for: page.background, size: size))
            if PageBackgroundRenderer.isFilled(page.background) {
                context.setFillColor(PageBackgroundRenderer.lineColor.cgColor)
                context.fillPath()
            } else {
                context.setStrokeColor(PageBackgroundRenderer.lineColor.cgColor)
                context.setLineWidth(PageBackgroundRenderer.lineWidth(for: page.background))
                context.strokePath()
            }
            let annotations = snapshot.markups.filter { $0.pageID == page.id }.map { $0.annotation() }
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            for annotation in annotations { annotation.draw(with: .cropBox, in: context) }
            context.restoreGState()
        }
        if let data = snapshot.drawings[page.id] {
            let drawing = try PKDrawing(data: data)
            if vectorInk {
                try PDFInkRenderer.draw(drawing, in: context, rect: rect)
            } else {
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    drawing.image(from: rect, scale: min(2, 4096 / max(size.width, size.height))).draw(in: rect)
                }
            }
        }
        PageItemRenderer.draw(snapshot.pageItems[page.id] ?? [], assets: snapshot.imageAssets, in: context)
    }
}
