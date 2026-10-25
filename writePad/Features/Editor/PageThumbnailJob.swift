import PDFKit
import PencilKit
import UIKit

/// What one thumbnail needs, copied so it can be rendered off the main actor.
struct PageThumbnailJob: Sendable {
    let id: UUID
    let version: Int
    let background: PageBackground
    let pdfPageIndex: Int?
    let drawing: PKDrawing
    let markups: [PDFMarkup]

    /// PDF pages come from a private copy of the document: the one on screen belongs to the PDF view.
    func render(document: PDFDocument?, width: CGFloat) -> UIImage {
        if let pdfPageIndex, let page = document?.page(at: pdfPageIndex) {
            for markup in markups { page.addAnnotation(markup.annotation()) }
            return PageBackgroundRenderer.thumbnail(pdfPage: page, drawing: drawing, width: width)
        }
        return PageBackgroundRenderer.thumbnail(background: background, drawing: drawing, width: width)
    }
}
