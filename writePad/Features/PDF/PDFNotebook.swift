import Observation
import PDFKit
import UIKit

@MainActor
@Observable
final class PDFNotebook {
    struct OutlineItem: Identifiable {
        let id = UUID()
        let title: String
        let pageID: UUID
        let depth: Int
    }

    let document: PDFDocument
    private(set) var markups: [PDFMarkup]
    private(set) var sourceComments: [PDFMarkup] = []
    private(set) var outline: [OutlineItem] = []
    private(set) var searchResults: [PDFSelection] = []
    private(set) var pages: [PageInfo] = []
    var isDrawing = false
    var onChange: ((UUID) -> Void)?
    @ObservationIgnored weak var view: PDFView?
    @ObservationIgnored private let sourcePages: [PDFPage]
    @ObservationIgnored private var appliedAnnotations: [(PDFPage, PDFAnnotation)] = []

    init(url: URL, pages: [PageInfo], markups: [PDFMarkup]) throws {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            throw NotebookStore.StoreError.invalidPDF
        }
        for info in pages {
            guard let index = info.pdfPageIndex else { continue }
            guard index >= 0, index < document.pageCount, let page = document.page(at: index) else {
                throw NotebookStore.StoreError.invalidPDF
            }
            let size = page.bounds(for: .cropBox).size
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                throw NotebookStore.StoreError.invalidPDF
            }
        }
        self.document = document
        self.sourcePages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        self.markups = markups
        for info in pages {
            guard let index = info.pdfPageIndex, sourcePages.indices.contains(index) else { continue }
            for annotation in sourcePages[index].annotations where annotation.type == "Text" {
                sourceComments.append(PDFMarkup(pageID: info.id, kind: .comment,
                                                bounds: annotation.bounds, text: annotation.contents ?? "Comment"))
            }
        }
        if let root = document.outlineRoot {
            self.outline = Self.outlineItems(root, document: document, pages: pages)
        }
        rebuild(pages: pages)
    }

    func rebuild(pages: [PageInfo]) {
        self.pages = pages
        searchResults = []
        for (page, annotation) in appliedAnnotations { page.removeAnnotation(annotation) }
        appliedAnnotations = []
        while document.pageCount > 0 { document.removePage(at: 0) }
        for (index, info) in pages.enumerated() {
            if let sourceIndex = info.pdfPageIndex, sourcePages.indices.contains(sourceIndex) {
                document.insert(sourcePages[sourceIndex], at: index)
            } else {
                let image = PageBackgroundRenderer.thumbnail(
                    background: info.background, drawing: .init(), width: PageLayout.pageSize.width
                )
                if let page = PDFPage(image: image) {
                    page.setBounds(CGRect(origin: .zero, size: PageLayout.pageSize), for: .mediaBox)
                    page.setBounds(CGRect(origin: .zero, size: PageLayout.pageSize), for: .cropBox)
                    document.insert(page, at: index)
                }
            }
        }
        for markup in markups { apply(markup) }
    }

    func pageID(for page: PDFPage) -> UUID? {
        let index = document.index(for: page)
        return pages.indices.contains(index) ? pages[index].id : nil
    }

    func page(for id: UUID) -> PDFPage? {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return nil }
        return document.page(at: index)
    }

    func search(_ query: String) {
        searchResults = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [] : document.findString(query, withOptions: [.caseInsensitive])
    }

    @discardableResult
    func annotate(_ selection: PDFSelection, kind: PDFMarkup.Kind) -> Int {
        guard kind != .comment else { return 0 }
        var count = 0
        for line in selection.selectionsByLine() {
            for page in line.pages {
                guard let id = pageID(for: page) else { continue }
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty, !bounds.isInfinite, !bounds.isNull else { continue }
                append(PDFMarkup(pageID: id, kind: kind, bounds: bounds, text: line.string ?? ""))
                count += 1
            }
        }
        return count
    }

    func addComment(_ text: String, pageID: UUID, at point: CGPoint? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let page = page(for: pageID) else { return }
        let crop = page.bounds(for: .cropBox)
        let origin = point ?? CGPoint(x: crop.minX + 24, y: crop.maxY - 48)
        append(PDFMarkup(pageID: pageID, kind: .comment,
                         bounds: CGRect(x: min(max(origin.x, crop.minX), crop.maxX - 24),
                                        y: min(max(origin.y, crop.minY), crop.maxY - 24), width: 24, height: 24), text: text))
    }

    func updateComment(id: UUID, text: String) {
        guard let index = markups.firstIndex(where: { $0.id == id }), markups[index].kind == .comment,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        markups[index].text = text
        refreshAnnotations()
        onChange?(markups[index].pageID)
    }

    func removeMarkup(id: UUID) {
        guard let markup = markups.first(where: { $0.id == id }) else { return }
        markups.removeAll { $0.id == id }
        refreshAnnotations()
        onChange?(markup.pageID)
    }

    private func append(_ markup: PDFMarkup) {
        markups.append(markup)
        apply(markup)
        onChange?(markup.pageID)
    }

    private func refreshAnnotations() {
        for (page, annotation) in appliedAnnotations { page.removeAnnotation(annotation) }
        appliedAnnotations = []
        for markup in markups { apply(markup) }
    }

    private func apply(_ markup: PDFMarkup) {
        guard let page = page(for: markup.pageID) else { return }
        let annotation = markup.annotation()
        page.addAnnotation(annotation)
        appliedAnnotations.append((page, annotation))
    }

    private static func outlineItems(_ root: PDFOutline, document: PDFDocument, pages: [PageInfo], depth: Int = 0) -> [OutlineItem] {
        (0..<root.numberOfChildren).flatMap { index -> [OutlineItem] in
            guard let child = root.child(at: index) else { return [] }
            var items: [OutlineItem] = []
            if let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination,
               let page = destination.page,
               let info = pages.first(where: { $0.pdfPageIndex == document.index(for: page) }) {
                items.append(OutlineItem(title: child.label ?? "Untitled", pageID: info.id, depth: depth))
            }
            return items + outlineItems(child, document: document, pages: pages, depth: depth + 1)
        }
    }
}
