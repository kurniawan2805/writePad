import CoreGraphics
import Foundation

/// A clean shape a hand-drawn stroke was recognized as, in the stroke's own coordinates.
enum RecognizedShape: Equatable {
    case line(CGPoint, CGPoint)
    /// `rotation` in radians; radii along the rotated x and y axes.
    case ellipse(center: CGPoint, radii: CGSize, rotation: CGFloat)
    /// A closed polygon: a triangle, or a rectangle squared up from four corners.
    case polygon([CGPoint])
}

/// Recognizes lines, ellipses, rectangles and triangles in stroke points. Pure geometry, so it is tested without UI.
/// Anything it isn't confident about returns nil and the stroke stays as drawn.
enum ShapeRecognizer {
    /// Smaller strokes are left alone: at that size a dot or a tick is more likely than a shape.
    static let minimumSize: CGFloat = 16

    static func recognize(_ input: [CGPoint]) -> RecognizedShape? {
        guard input.count >= 2 else { return nil }
        let box = boundingBox(input)
        let diagonal = hypot(box.width, box.height)
        guard diagonal >= minimumSize else { return nil }
        let points = resample(input, spacing: diagonal / 64)
        guard points.count >= 4, let first = points.first, let last = points.last else { return nil }
        let length = pathLength(points)

        if let line = line(points, length: length) { return line }

        // Everything else must be closed: the pen came back near where it started, around the whole shape.
        let gap = distance(first, last)
        guard gap <= max(12, diagonal * 0.25), length >= diagonal * 1.8 else { return nil }
        return closedShape(points, diagonal: diagonal)
    }

    /// Dense points along the shape for a `PKStrokePath`. Corners are repeated so the path's B-spline passes through
    /// them instead of rounding them off.
    static func outline(of shape: RecognizedShape, spacing: CGFloat = 4) -> [CGPoint] {
        switch shape {
        case let .line(start, end):
            return [start, start] + sample(from: start, to: end, spacing: spacing) + [end, end]
        case let .polygon(corners):
            var points: [CGPoint] = []
            for (index, corner) in corners.enumerated() {
                let next = corners[(index + 1) % corners.count]
                points += [corner, corner, corner]
                points += sample(from: corner, to: next, spacing: spacing).dropFirst()
            }
            return points + [corners[0], corners[0], corners[0]]
        case let .ellipse(center, radii, rotation):
            let circumference = 2 * .pi * sqrt((radii.width * radii.width + radii.height * radii.height) / 2)
            let count = max(24, Int(circumference / spacing))
            let points = (0...count).map { step -> CGPoint in
                let angle = 2 * .pi * CGFloat(step) / CGFloat(count)
                let local = CGPoint(x: radii.width * cos(angle), y: radii.height * sin(angle))
                return rotate(local, by: rotation).offset(by: center)
            }
            // Overlap the start a little so the closed curve has no visible seam.
            return points + points.prefix(3)
        }
    }

    // MARK: Lines

    private static func line(_ points: [CGPoint], length: CGFloat) -> RecognizedShape? {
        guard let start = points.first, let end = points.last else { return nil }
        let chord = distance(start, end)
        guard chord >= minimumSize, length <= chord * 1.12 else { return nil }
        let deviation = points.map { distance($0, toSegment: start, end) }.max() ?? 0
        guard deviation <= max(4, chord * 0.05) else { return nil }
        return .line(start, snapAngle(of: start, end))
    }

    /// Nearly horizontal or vertical lines become exactly so, keeping the start point and the length.
    private static func snapAngle(of start: CGPoint, _ end: CGPoint) -> CGPoint {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let nearest = (angle / (.pi / 2)).rounded() * (.pi / 2)
        guard abs(angle - nearest) < 4 * .pi / 180 else { return end }
        let length = distance(start, end)
        return CGPoint(x: start.x + length * cos(nearest), y: start.y + length * sin(nearest))
    }

    // MARK: Closed shapes

    private static func closedShape(_ points: [CGPoint], diagonal: CGFloat) -> RecognizedShape? {
        let corners = closedCorners(points, diagonal: diagonal)
        let ellipse = fitEllipse(points)
        let ellipseError = ellipse.map { ellipseFitError(points, $0) } ?? .infinity

        if corners.count == 4, let rectangle = squaredRectangle(points, corners: corners) {
            let error = polygonFitError(points, rectangle) / diagonal
            if error < 0.035, error < ellipseError * 0.6 { return .polygon(rectangle) }
        }
        if corners.count == 3 {
            let error = polygonFitError(points, corners) / diagonal
            if error < 0.035, error < ellipseError * 0.6 { return .polygon(corners) }
        }
        if let ellipse, ellipseError < 0.1 { return roundedOff(ellipse) }
        return nil
    }

    /// Corners of a closed stroke: Douglas–Peucker on the closed polyline, with near-duplicates merged.
    private static func closedCorners(_ points: [CGPoint], diagonal: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var corners = Array(simplify(points + [first], epsilon: diagonal * 0.07).dropLast())
        // The stroke's start is not necessarily a corner: drop it if it lies on the edge between its neighbours.
        if corners.count > 3, let start = corners.first, let after = corners.dropFirst().first, let before = corners.last,
           distance(start, toSegment: before, after) < diagonal * 0.07 {
            corners.removeFirst()
        }
        var merged: [CGPoint] = []
        for corner in corners where merged.allSatisfy({ distance($0, corner) > diagonal * 0.15 }) {
            merged.append(corner)
        }
        return merged
    }

    /// Four rough corners become a true rectangle aligned with the average edge direction (or the axes, if close).
    private static func squaredRectangle(_ points: [CGPoint], corners: [CGPoint]) -> [CGPoint]? {
        let angles = corners.indices.map { index -> CGFloat in
            let next = corners[(index + 1) % corners.count]
            return atan2(next.y - corners[index].y, next.x - corners[index].x)
        }
        // Right angles only: each turn between edges must be within 25° of 90°.
        for index in angles.indices {
            var turn = abs(angles[(index + 1) % angles.count] - angles[index]).truncatingRemainder(dividingBy: .pi)
            turn = min(turn, .pi - turn)
            guard abs(turn - .pi / 2) < 25 * .pi / 180 else { return nil }
        }
        // Average edge direction modulo 90°, via the 4θ trick so 0° and 90° edges agree.
        let sum = angles.reduce(CGPoint.zero) { CGPoint(x: $0.x + cos(4 * $1), y: $0.y + sin(4 * $1)) }
        var rotation = atan2(sum.y, sum.x) / 4
        if abs(rotation) < 6 * .pi / 180 { rotation = 0 }
        let unrotated = points.map { rotate($0, by: -rotation) }
        let box = boundingBox(unrotated)
        let local = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                     CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        return local.map { rotate($0, by: rotation) }
    }

    private struct Ellipse {
        var center: CGPoint
        var radii: CGSize
        var rotation: CGFloat
    }

    /// Orientation from the points' principal axis, size from their extent along it.
    private static func fitEllipse(_ points: [CGPoint]) -> Ellipse? {
        let count = CGFloat(points.count)
        let mean = CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
        var sumXX: CGFloat = 0, sumYY: CGFloat = 0, sumXY: CGFloat = 0
        for point in points {
            let dx = point.x - mean.x, dy = point.y - mean.y
            sumXX += dx * dx
            sumYY += dy * dy
            sumXY += dx * dy
        }
        let rotation = 0.5 * atan2(2 * sumXY, sumXX - sumYY)
        let local = points.map { rotate($0.offset(by: CGPoint(x: -mean.x, y: -mean.y)), by: -rotation) }
        let box = boundingBox(local)
        guard box.width > 1, box.height > 1 else { return nil }
        let center = rotate(CGPoint(x: box.midX, y: box.midY), by: rotation).offset(by: mean)
        return Ellipse(center: center, radii: CGSize(width: box.width / 2, height: box.height / 2), rotation: rotation)
    }

    /// Mean distance from the unit ellipse, as a fraction of its size.
    private static func ellipseFitError(_ points: [CGPoint], _ ellipse: Ellipse) -> CGFloat {
        let total = points.reduce(CGFloat(0)) { sum, point in
            let local = rotate(point.offset(by: CGPoint(x: -ellipse.center.x, y: -ellipse.center.y)), by: -ellipse.rotation)
            let radius = hypot(local.x / ellipse.radii.width, local.y / ellipse.radii.height)
            return sum + abs(radius - 1)
        }
        return total / CGFloat(points.count)
    }

    /// Near-circles become circles, and near-axis ellipses lose their tilt.
    private static func roundedOff(_ ellipse: Ellipse) -> RecognizedShape {
        var ellipse = ellipse
        let larger = max(ellipse.radii.width, ellipse.radii.height)
        if abs(ellipse.radii.width - ellipse.radii.height) / larger < 0.12 {
            let radius = (ellipse.radii.width + ellipse.radii.height) / 2
            ellipse.radii = CGSize(width: radius, height: radius)
            ellipse.rotation = 0
        } else {
            let quarter = CGFloat.pi / 2
            let nearest = (ellipse.rotation / quarter).rounded() * quarter
            if abs(ellipse.rotation - nearest) < 8 * .pi / 180 {
                // A quarter turn swaps which radius lies along x.
                if Int((nearest / quarter).rounded()) % 2 != 0 {
                    ellipse.radii = CGSize(width: ellipse.radii.height, height: ellipse.radii.width)
                }
                ellipse.rotation = 0
            }
        }
        return .ellipse(center: ellipse.center, radii: ellipse.radii, rotation: ellipse.rotation)
    }

    private static func polygonFitError(_ points: [CGPoint], _ corners: [CGPoint]) -> CGFloat {
        let total = points.reduce(CGFloat(0)) { sum, point in
            sum + corners.indices.map { distance(point, toSegment: corners[$0], corners[($0 + 1) % corners.count]) }.min()!
        }
        return total / CGFloat(points.count)
    }

    // MARK: Geometry

    static func resample(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard var previous = points.first, spacing > 0 else { return points }
        var result = [previous]
        var carried: CGFloat = 0
        for point in points.dropFirst() {
            var segment = distance(previous, point)
            var start = previous
            while carried + segment >= spacing {
                let fraction = (spacing - carried) / segment
                start = CGPoint(x: start.x + (point.x - start.x) * fraction, y: start.y + (point.y - start.y) * fraction)
                result.append(start)
                segment = distance(start, point)
                carried = 0
            }
            carried += segment
            previous = point
        }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }

    private static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest = 0
        var farthestDistance: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let candidate = distance(points[index], toSegment: first, last)
            if candidate > farthestDistance {
                farthest = index
                farthestDistance = candidate
            }
        }
        guard farthestDistance > epsilon else { return [first, last] }
        let left = simplify(Array(points[...farthest]), epsilon: epsilon)
        let right = simplify(Array(points[farthest...]), epsilon: epsilon)
        return left.dropLast() + right
    }

    private static func sample(from start: CGPoint, to end: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let steps = max(1, Int(distance(start, end) / spacing))
        return (0...steps).map { step in
            let fraction = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        }
    }

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xValues = points.map(\.x), yValues = points.map(\.y)
        guard let minX = xValues.min(), let maxX = xValues.max(), let minY = yValues.min(), let maxY = yValues.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func distance(_ point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, start) }
        let fraction = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        return distance(point, CGPoint(x: start.x + fraction * dx, y: start.y + fraction * dy))
    }

    private static func rotate(_ point: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(x: point.x * cos(angle) - point.y * sin(angle), y: point.x * sin(angle) + point.y * cos(angle))
    }
}

private extension CGPoint {
    func offset(by delta: CGPoint) -> CGPoint {
        CGPoint(x: x + delta.x, y: y + delta.y)
    }
}
