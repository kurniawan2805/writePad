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

    /// PDF pages come from a private copy of the document: the one on screen belongs to the PDF view.
    func render(document: PDFDocument?, width: CGFloat) -> UIImage {
        if let pdfPageIndex, let page = document?.page(at: pdfPageIndex) {
            for markup in markups { page.addAnnotation(markup.annotation()) }
            return PageBackgroundRenderer.thumbnail(pdfPage: page, drawing: drawing, width: width)
        }
        return PageBackgroundRenderer.thumbnail(background: background, drawing: drawing, width: width)
    }
}
