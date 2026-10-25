import PDFKit
import UIKit

/// Writes markups into an exported PDF as real annotations, so other apps can read comments and edit highlights.
/// Exported pages are the source crop box drawn upright, so each annotation is moved from source page space by the
/// page's crop-box transform; underline and strikeout quad points keep the direction of the text.
enum PDFExportAnnotations {
    enum WriteError: LocalizedError {
        case unreadable, unwritable

        var errorDescription: String? { "The annotations couldn't be added to the exported PDF." }
    }

    static func add(to url: URL, pages: [PageInfo], markups: [PDFMarkup], source: PDFDocument?) throws {
        let pageIDs = Set(pages.map(\.id))
        let sourceComments = pages.contains { page in
            page.pdfPageIndex.flatMap { source?.page(at: $0) }.map { !comments(on: $0).isEmpty } ?? false
        }
        guard sourceComments || markups.contains(where: { pageIDs.contains($0.pageID) }) else { return }
        guard let output = PDFDocument(url: url) else { throw WriteError.unreadable }
        for (index, page) in pages.enumerated() {
            guard let target = output.page(at: index) else { throw WriteError.unreadable }
            let sourcePage = page.pdfPageIndex.flatMap { source?.page(at: $0) }
            let transform = sourcePage?.transform(for: .cropBox) ?? .identity
            for original in sourcePage.map(comments(on:)) ?? [] where original.type == "Text" {
                target.addAnnotation(comment(at: original.bounds, text: original.contents ?? "", transform: transform,
                                             from: original))
            }
            for markup in markups where markup.pageID == page.id {
                target.addAnnotation(annotation(for: markup, transform: transform))
            }
        }
        guard output.write(to: url) else { throw WriteError.unwritable }
    }

    /// Sticky notes that came with the source PDF (and their popups); exported as live annotations instead of
    /// flattened icons.
    static func comments(on page: PDFPage) -> [PDFAnnotation] {
        let notes = page.annotations.filter { $0.type == "Text" }
        return notes + notes.compactMap(\.popup)
    }

    static func annotation(for markup: PDFMarkup, transform: CGAffineTransform) -> PDFAnnotation {
        if markup.kind == .comment {
            return comment(at: markup.bounds, text: markup.text, transform: transform, from: markup.annotation())
        }
        let bounds = markup.bounds.applying(transform)
        let annotation = PDFAnnotation(bounds: bounds, forType: markup.kind.subtype, withProperties: nil)
        let template = markup.annotation()
        annotation.color = template.color
        annotation.contents = template.contents
        annotation.userName = template.userName
        // Upper left, upper right, lower left, lower right of the text, relative to the annotation's origin.
        let rect = markup.bounds
        annotation.quadrilateralPoints = [
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
        ].map { point in
            let moved = point.applying(transform)
            return NSValue(cgPoint: CGPoint(x: moved.x - bounds.minX, y: moved.y - bounds.minY))
        }
        return annotation
    }

    /// Note icons stay upright and the same size; only their corner moves.
    private static func comment(at rect: CGRect, text: String, transform: CGAffineTransform,
                                from template: PDFAnnotation) -> PDFAnnotation {
        let moved = rect.applying(transform)
        let bounds = CGRect(x: moved.minX, y: moved.maxY - rect.height, width: rect.width, height: rect.height)
        let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        annotation.contents = text
        annotation.color = template.color
        annotation.iconType = template.iconType
        annotation.userName = template.userName
        return annotation
    }
}
