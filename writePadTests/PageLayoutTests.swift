import PencilKit
import Testing
@testable import writePad

struct PageLayoutTests {
    let layout = PageLayout(pageCount: 3)

    @Test func pagesStackVerticallyWithSpacing() {
        let first = layout.frame(ofPage: 0)
        let second = layout.frame(ofPage: 1)
        #expect(first.origin == CGPoint(x: PageLayout.padding, y: PageLayout.padding))
        #expect(second.minY == first.maxY + PageLayout.spacing)
        #expect(layout.contentSize.height == layout.frame(ofPage: 2).maxY + PageLayout.padding)
    }

    @Test func gapIsSplitHalfwayBetweenPages() {
        let gapMiddle = layout.frame(ofPage: 0).maxY + PageLayout.spacing / 2
        #expect(layout.pageIndex(atY: gapMiddle - 1) == 0)
        #expect(layout.pageIndex(atY: gapMiddle + 1) == 1)
        #expect(layout.pageIndex(atY: -500) == 0)
        #expect(layout.pageIndex(atY: 1_000_000) == 2)
    }

    @Test func mergeThenSplitRoundTrips() {
        let pages = [
            PKDrawing(strokes: [Self.stroke(at: CGPoint(x: 100, y: 100))]),
            PKDrawing(),
            PKDrawing(strokes: [Self.stroke(at: CGPoint(x: 50, y: 900)), Self.stroke(at: CGPoint(x: 300, y: 20))]),
        ]
        let split = layout.split(layout.merge(pages))

        #expect(split.map(\.strokes.count) == [1, 0, 2])
        for (original, roundTripped) in zip(pages, split) {
            for (before, after) in zip(original.strokes, roundTripped.strokes) {
                #expect(abs(before.renderBounds.midX - after.renderBounds.midX) < 0.001)
                #expect(abs(before.renderBounds.midY - after.renderBounds.midY) < 0.001)
            }
        }
    }

    @Test func strokeDrawnOnCanvasLandsOnPageUnderIt() {
        let onThirdPage = layout.frame(ofPage: 2).origin.applying(CGAffineTransform(translationX: 10, y: 40))
        let split = layout.split(PKDrawing(strokes: [Self.stroke(at: onThirdPage)]))

        #expect(split.map(\.strokes.count) == [0, 0, 1])
        let local = split[2].strokes[0].renderBounds
        #expect(abs(local.midX - 10) < 1 && abs(local.midY - 40) < 1)
    }

    /// A short horizontal stroke centered on `center`.
    static func stroke(at center: CGPoint) -> PKStroke {
        let points = (-2...2).map { step in
            PKStrokePoint(location: CGPoint(x: center.x + CGFloat(step) * 5, y: center.y), timeOffset: 0.01 * Double(step + 2),
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }
}
