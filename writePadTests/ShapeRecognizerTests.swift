import CoreGraphics
import Foundation
import Testing
@testable import writePad

/// Hand-drawn strokes are simulated with seeded noise, so every run sees the same wobble.
struct ShapeRecognizerTests {
    /// A small deterministic generator (SplitMix64).
    struct Wobble {
        var state: UInt64

        mutating func next(_ amplitude: CGFloat) -> CGFloat {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return (CGFloat(value % 10_000) / 5_000 - 1) * amplitude
        }

        mutating func shake(_ points: [CGPoint], _ amplitude: CGFloat) -> [CGPoint] {
            points.map { CGPoint(x: $0.x + next(amplitude), y: $0.y + next(amplitude)) }
        }
    }

    static func segment(_ start: CGPoint, _ end: CGPoint, steps: Int = 30) -> [CGPoint] {
        (0...steps).map { step in
            let fraction = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
    }

    static func polyline(_ corners: [CGPoint], closed: Bool) -> [CGPoint] {
        let ends = closed ? corners + [corners[0]] : corners
        return zip(ends, ends.dropFirst()).flatMap { segment($0, $1).dropLast() } + [ends.last!]
    }

    static func ellipse(center: CGPoint, radii: CGSize, rotation: CGFloat = 0, sweep: CGFloat = 2 * .pi,
                        start: CGFloat = 0) -> [CGPoint] {
        (0...80).map { step in
            let angle = start + sweep * CGFloat(step) / 80
            let x = radii.width * cos(angle), y = radii.height * sin(angle)
            return CGPoint(x: center.x + x * cos(rotation) - y * sin(rotation),
                           y: center.y + x * sin(rotation) + y * cos(rotation))
        }
    }

    // MARK: Recognized

    @Test func wobblyLineBecomesStraight() throws {
        var wobble = Wobble(state: 1)
        let points = wobble.shake(Self.segment(CGPoint(x: 40, y: 50), CGPoint(x: 300, y: 140)), 2)
        guard case let .line(start, end) = ShapeRecognizer.recognize(points) else {
            Issue.record("expected a line")
            return
        }
        #expect(abs(start.x - points[0].x) < 0.001 && abs(start.y - points[0].y) < 0.001)
        #expect(hypot(end.x - 300, end.y - 140) < 6)
    }

    @Test func nearlyHorizontalLineIsLevelled() throws {
        var wobble = Wobble(state: 2)
        let points = wobble.shake(Self.segment(CGPoint(x: 20, y: 100), CGPoint(x: 320, y: 112)), 1.5)
        guard case let .line(start, end) = ShapeRecognizer.recognize(points) else {
            Issue.record("expected a line")
            return
        }
        #expect(abs(end.y - start.y) < 0.001)
    }

    @Test func circleIsRecognizedAsCircle() throws {
        var wobble = Wobble(state: 3)
        let points = wobble.shake(Self.ellipse(center: CGPoint(x: 200, y: 200), radii: CGSize(width: 80, height: 76)), 3)
        guard case let .ellipse(center, radii, rotation) = ShapeRecognizer.recognize(points) else {
            Issue.record("expected an ellipse")
            return
        }
        #expect(hypot(center.x - 200, center.y - 200) < 6)
        #expect(radii.width == radii.height)
        #expect(abs(radii.width - 78) < 6)
        #expect(rotation == 0)
    }

    @Test func tiltedEllipseKeepsItsTilt() throws {
        var wobble = Wobble(state: 4)
        let tilt = CGFloat.pi / 6
        let points = wobble.shake(Self.ellipse(center: CGPoint(x: 300, y: 260), radii: CGSize(width: 140, height: 60),
                                               rotation: tilt), 3)
        guard case let .ellipse(_, radii, rotation) = ShapeRecognizer.recognize(points) else {
            Issue.record("expected an ellipse")
            return
        }
        let major = max(radii.width, radii.height), minor = min(radii.width, radii.height)
        #expect(abs(major - 140) < 12 && abs(minor - 60) < 10)
        let difference = abs(rotation - tilt).truncatingRemainder(dividingBy: .pi)
        #expect(min(difference, .pi - difference) < 0.12)
    }

    @Test func roughRectangleIsSquaredUp() throws {
        var wobble = Wobble(state: 5)
        // Start mid-edge, as people often do.
        let corners = [CGPoint(x: 150, y: 100), CGPoint(x: 300, y: 102), CGPoint(x: 298, y: 220),
                       CGPoint(x: 101, y: 218), CGPoint(x: 100, y: 101)]
        let points = wobble.shake(Self.polyline(corners, closed: true), 2.5)
        guard case let .polygon(result) = ShapeRecognizer.recognize(points) else {
            Issue.record("expected a rectangle")
            return
        }
        #expect(result.count == 4)
        let box = ShapeRecognizer.boundingBox(result)
        #expect(abs(box.minX - 100) < 8 && abs(box.maxX - 300) < 8)
        #expect(abs(box.minY - 100) < 8 && abs(box.maxY - 220) < 8)
        // Axis-aligned: every edge is exactly horizontal or vertical.
        for (corner, next) in zip(result, result.dropFirst() + [result[0]]) {
            #expect(abs(corner.x - next.x) < 0.001 || abs(corner.y - next.y) < 0.001)
        }
    }

    @Test func rotatedSquareStaysRotated() throws {
        var wobble = Wobble(state: 6)
        let center = CGPoint(x: 250, y: 250), half: CGFloat = 90, angle = CGFloat.pi / 7
        let corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { signX, signY -> CGPoint in
            let x = CGFloat(signX) * half, y = CGFloat(signY) * half
            return CGPoint(x: center.x + x * cos(angle) - y * sin(angle), y: center.y + x * sin(angle) + y * cos(angle))
        }
        let points = wobble.shake(Self.polyline(corners, closed: true), 2)
        guard case let .polygon(result) = ShapeRecognizer.recognize(points) else {
            Issue.record("expected a square")
            return
        }
        #expect(result.count == 4)
        let edge = atan2(result[1].y - result[0].y, result[1].x - result[0].x)
        let offAxis = abs(edge.truncatingRemainder(dividingBy: .pi / 2))
        #expect(min(offAxis, .pi / 2 - offAxis) > 0.3, "a 26° square must not be snapped to the axes")
    }

    @Test func triangleKeepsThreeCorners() throws {
        var wobble = Wobble(state: 7)
        let corners = [CGPoint(x: 200, y: 60), CGPoint(x: 330, y: 280), CGPoint(x: 70, y: 280)]
        let points = wobble.shake(Self.polyline(corners, closed: true), 2)
        guard case let .polygon(result) = ShapeRecognizer.recognize(points) else {
            Issue.record("expected a triangle")
            return
        }
        #expect(result.count == 3)
        for corner in corners {
            #expect(result.contains { hypot($0.x - corner.x, $0.y - corner.y) < 15 })
        }
    }

    // MARK: Left alone

    @Test func handwritingAndOpenCurvesAreLeftAlone() {
        var wobble = Wobble(state: 8)
        let zigzag = Self.polyline((0..<8).map { CGPoint(x: 40 + CGFloat($0) * 30, y: $0 % 2 == 0 ? 100 : 160) },
                                   closed: false)
        let sCurve = (0...80).map { step -> CGPoint in
            let progress = CGFloat(step) / 80
            return CGPoint(x: 100 + 60 * sin(progress * 2 * .pi), y: 100 + 200 * progress)
        }
        let arc = Self.ellipse(center: CGPoint(x: 200, y: 200), radii: CGSize(width: 90, height: 90), sweep: .pi * 1.2)
        let tick = Self.polyline([CGPoint(x: 100, y: 100), CGPoint(x: 120, y: 130), CGPoint(x: 170, y: 40)], closed: false)
        let dot = Self.segment(CGPoint(x: 10, y: 10), CGPoint(x: 14, y: 12))
        let scribble = (0..<120).map { _ in CGPoint(x: 150 + wobble.next(60), y: 150 + wobble.next(60)) }

        #expect(ShapeRecognizer.recognize(wobble.shake(zigzag, 1)) == nil)
        #expect(ShapeRecognizer.recognize(sCurve) == nil)
        #expect(ShapeRecognizer.recognize(arc) == nil)
        #expect(ShapeRecognizer.recognize(tick) == nil)
        #expect(ShapeRecognizer.recognize(dot) == nil)
        #expect(ShapeRecognizer.recognize(scribble) == nil)
    }

    // MARK: Outline

    @Test func outlinePassesThroughCornersAndCloses() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        let outline = ShapeRecognizer.outline(of: .polygon(square))
        for corner in square {
            let repeats = zip(outline, outline.dropFirst()).filter { $0 == corner && $1 == corner }.count
            #expect(repeats >= 2, "corners repeat so the spline stays sharp")
        }
        #expect(outline.first == outline.last)
        let gaps = zip(outline, outline.dropFirst()).map { hypot($0.x - $1.x, $0.y - $1.y) }
        #expect(gaps.max()! <= 4.01)
    }
}
