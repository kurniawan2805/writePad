import CoreGraphics
import PencilKit

/// Geometry of pages stacked vertically on one canvas, in unzoomed canvas points.
///
/// Drawings are persisted per page in page coordinates (origin at the page's top-left);
/// `merge` and `split` convert between those and the single combined canvas drawing.
struct PageLayout: Equatable {
    /// A4 at 96 dpi.
    static let pageSize = CGSize(width: 794, height: 1123)
    static let spacing: CGFloat = 24
    static let padding: CGFloat = 24

    let pageCount: Int

    private var pitch: CGFloat { Self.pageSize.height + Self.spacing }

    var contentSize: CGSize {
        CGSize(
            width: Self.pageSize.width + 2 * Self.padding,
            height: 2 * Self.padding + CGFloat(pageCount) * pitch - Self.spacing
        )
    }

    func frame(ofPage index: Int) -> CGRect {
        CGRect(origin: CGPoint(x: Self.padding, y: Self.padding + CGFloat(index) * pitch), size: Self.pageSize)
    }

    /// The page owning canvas position `y`; the gap between two pages is split halfway.
    func pageIndex(atY y: CGFloat) -> Int {
        let index = Int(((y - Self.padding + Self.spacing / 2) / pitch).rounded(.down))
        return min(max(index, 0), pageCount - 1)
    }

    /// Places each page-local drawing at its page's position on the canvas.
    func merge(_ pageDrawings: [PKDrawing]) -> PKDrawing {
        var strokes: [PKStroke] = []
        for (index, drawing) in pageDrawings.enumerated() {
            let origin = frame(ofPage: index).origin
            let shift = CGAffineTransform(translationX: origin.x, y: origin.y)
            strokes += drawing.strokes.map { stroke in
                var stroke = stroke
                stroke.transform = stroke.transform.concatenating(shift)
                return stroke
            }
        }
        return PKDrawing(strokes: strokes)
    }

    /// Assigns each stroke to the page under its center and converts it to page coordinates.
    func split(_ drawing: PKDrawing) -> [PKDrawing] {
        var strokesByPage = Array(repeating: [PKStroke](), count: pageCount)
        for stroke in drawing.strokes {
            let index = pageIndex(atY: stroke.renderBounds.midY)
            let origin = frame(ofPage: index).origin
            var local = stroke
            local.transform = stroke.transform.concatenating(CGAffineTransform(translationX: -origin.x, y: -origin.y))
            strokesByPage[index].append(local)
        }
        return strokesByPage.map(PKDrawing.init(strokes:))
    }
}
