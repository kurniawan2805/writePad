import PencilKit
import Testing
import UIKit
@testable import writePad

@MainActor
struct ShapeSnapperTests {
    /// A canvas with its own undo manager, since a test canvas has no window to borrow one from.
    final class TestCanvas: PKCanvasView {
        let undo = UndoManager()
        override var undoManager: UndoManager? { undo }
    }

    static func stroke(_ points: [CGPoint], ink: PKInk = PKInk(.marker, color: .systemBlue),
                       transform: CGAffineTransform = .identity) -> PKStroke {
        let path = points.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) * 0.01, size: CGSize(width: 6, height: 6),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: path, creationDate: .now), transform: transform)
    }

    static var wobblyLine: [CGPoint] {
        var wobble = ShapeRecognizerTests.Wobble(state: 11)
        return wobble.shake(ShapeRecognizerTests.segment(CGPoint(x: 50, y: 80), CGPoint(x: 350, y: 90)), 2)
    }

    /// Lets the snapper's deferred replacement run.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(30))
    }

    @Test func snappedStrokeKeepsInkTransformAndPlace() throws {
        let shift = CGAffineTransform(translationX: 0, y: 1_000)
        let original = Self.stroke(Self.wobblyLine, transform: shift)
        let snapped = try #require(ShapeSnapper.snapped(original))

        #expect(snapped.ink.inkType == original.ink.inkType)
        #expect(snapped.ink.color == original.ink.color)
        #expect(snapped.transform == shift)
        let locations = snapped.path.map(\.location)
        #expect(Set(locations.map(\.y)).count == 1, "a nearly level line is levelled")
        #expect(abs(snapped.renderBounds.midY - original.renderBounds.midY) < 10)
    }

    @Test func handwritingIsNotSnapped() {
        let zigzag = (0..<8).map { CGPoint(x: 40 + CGFloat($0) * 30, y: $0 % 2 == 0 ? 100 : 160) }
        #expect(ShapeSnapper.snapped(Self.stroke(zigzag)) == nil)
    }

    @Test func heldStrokeIsSnappedWhetherPencilKitAddsItBeforeOrAfterTheTouchEnds() async throws {
        for strokeArrivesFirst in [true, false] {
            let canvas = TestCanvas()
            let snapper = ShapeSnapper(canvas: canvas) { true }
            snapper.strokeBegan()
            let raw = Self.stroke(Self.wobblyLine)
            if strokeArrivesFirst {
                canvas.drawing = PKDrawing(strokes: [raw])
                snapper.drawingDidChange()
                snapper.strokeEnded(heldStill: 0.6)
            } else {
                snapper.strokeEnded(heldStill: 0.6)
                canvas.drawing = PKDrawing(strokes: [raw])
                snapper.drawingDidChange()
            }
            try await settle()
            let result = try #require(canvas.drawing.strokes.first)
            #expect(canvas.drawing.strokes.count == 1)
            #expect(Set(result.path.map(\.location.y)).count == 1, "snapped when the stroke arrived first: \(strokeArrivesFirst)")
        }
    }

    @Test func quickStrokeOrDisabledSettingLeavesTheStrokeAlone() async throws {
        for (held, enabled) in [(0.1, true), (0.8, false)] {
            let canvas = TestCanvas()
            let snapper = ShapeSnapper(canvas: canvas) { enabled }
            snapper.strokeBegan()
            let raw = Self.stroke(Self.wobblyLine)
            canvas.drawing = PKDrawing(strokes: [raw])
            snapper.drawingDidChange()
            snapper.strokeEnded(heldStill: held)
            try await settle()
            #expect(canvas.drawing.strokes.first?.path.map(\.location) == raw.path.map(\.location))
        }
    }

    @Test func undoBringsBackTheHandDrawnStrokeAndRedoSnapsAgain() async throws {
        let canvas = TestCanvas()
        let snapper = ShapeSnapper(canvas: canvas) { true }
        snapper.strokeBegan()
        let raw = Self.stroke(Self.wobblyLine)
        canvas.drawing = PKDrawing(strokes: [raw])
        snapper.strokeEnded(heldStill: 0.6)
        try await settle()
        let snappedPoints = try #require(canvas.drawing.strokes.first).path.map(\.location)
        #expect(snappedPoints != raw.path.map(\.location))

        canvas.undo.undo()
        #expect(canvas.drawing.strokes.first?.path.map(\.location) == raw.path.map(\.location))
        try await settle()
        canvas.undo.redo()
        #expect(canvas.drawing.strokes.first?.path.map(\.location) == snappedPoints)
    }

    @Test func eraserOrLassoChangesAreNotSnapped() async throws {
        let canvas = TestCanvas()
        let first = Self.stroke(Self.wobblyLine)
        canvas.drawing = PKDrawing(strokes: [first, first])
        let snapper = ShapeSnapper(canvas: canvas) { true }
        snapper.strokeBegan()
        // An eraser touch removed a stroke instead of adding one.
        canvas.drawing = PKDrawing(strokes: [first])
        snapper.drawingDidChange()
        snapper.strokeEnded(heldStill: 1)
        try await settle()
        #expect(canvas.drawing.strokes.first?.path.map(\.location) == first.path.map(\.location))
    }
}
