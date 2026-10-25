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
    @Test func templatesUseTheirSpecifiedPageCoordinates() {
        let size = PageLayout.pageSize
        func points(_ background: PageBackground) -> [CGPoint] {
            var result: [CGPoint] = []
            PageBackgroundRenderer.patternPath(for: background).applyWithBlock { element in
                if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                    result.append(element.pointee.points[0])
                }
            }
            return result
        }
        let cornell = points(.cornell)
        #expect(cornell[0] == CGPoint(x: size.width * 0.25, y: 0))
        #expect(cornell[1] == CGPoint(x: size.width * 0.25, y: size.height * 0.8))
        #expect(cornell[2] == CGPoint(x: 0, y: size.height * 0.8))
        #expect(cornell[4] == CGPoint(x: size.width * 0.25, y: 32))
        let music = points(.music)
        #expect(music.count == 100)
        #expect(music[0] == CGPoint(x: 48, y: 48))
        #expect(music[10] == CGPoint(x: 48, y: 120))
        #expect(music.last == CGPoint(x: size.width - 48, y: 728))
        let planner = points(.plannerWeek)
        #expect(planner.count == 26)
        #expect(planner[0] == CGPoint(x: 0, y: 40))
        #expect(planner.contains(CGPoint(x: 0, y: size.height / 7)))
        #expect(PageBackgroundRenderer.lineWidth(for: .plannerWeek) == 1)
    }

    static func stroke(at center: CGPoint) -> PKStroke {
        let points = (-2...2).map { step in
            PKStrokePoint(location: CGPoint(x: center.x + CGFloat(step) * 5, y: center.y), timeOffset: 0.01 * Double(step + 2),
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }
}
