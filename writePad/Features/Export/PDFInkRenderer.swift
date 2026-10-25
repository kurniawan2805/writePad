import PencilKit
import UIKit

/// Builds vector nib coverage from PencilKit's public, interpolated stroke data.
enum PDFInkRenderer {
    static func draw(_ drawing: PKDrawing, in context: CGContext, rect: CGRect) throws {
        var textured: [PKStroke] = []
        for stroke in drawing.strokes {
            try Task.checkCancellation()
            guard stroke.renderBounds.intersects(rect) else { continue }
            if isVector(stroke.ink.inkType) {
                rasterize(textured, in: context, rect: rect)
                textured.removeAll(keepingCapacity: true)
                try draw(stroke, in: context)
            } else {
                textured.append(stroke)
            }
        }
        rasterize(textured, in: context, rect: rect)
    }

    private static func isVector(_ ink: PKInk.InkType) -> Bool {
        ink == .pen || ink == .monoline || ink == .marker
    }

    private static func rasterize(_ strokes: [PKStroke], in context: CGContext, rect: CGRect) {
        guard !strokes.isEmpty else { return }
        let drawing = PKDrawing(strokes: strokes)
        let bounds = drawing.bounds.insetBy(dx: -1, dy: -1).intersection(rect)
        guard !bounds.isNull, !bounds.isEmpty else { return }
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            drawing.image(from: bounds, scale: min(2, 4096 / max(rect.width, rect.height))).draw(in: bounds)
        }
    }

    private static func draw(_ stroke: PKStroke, in context: CGContext) throws {
        guard !stroke.path.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(stroke.transform)
        if let mask = stroke.mask {
            context.addPath(mask.cgPath)
            context.clip(using: mask.usesEvenOddFillRule ? .evenOdd : .winding)
        }
        let color = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        if stroke.ink.inkType == .marker {
            // Apply the ink color's alpha once, after the marker's pigment has accumulated.
            context.setAlpha(color.cgColor.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { context.endTransparencyLayer() }
            try drawMarker(stroke, color: color.withAlphaComponent(1), in: context)
            return
        }
        let coverage = CGMutablePath()
        var iterator = stroke.path.interpolatedPoints(by: .distance(0.5)).makeIterator()
        let last = stroke.path.interpolatedPoint(at: CGFloat(stroke.path.count - 1))
        var current = iterator.next()
        var previous = current?.location ?? last.location
        var count = 0
        var edges: (CGPoint, CGPoint)?
        while let point = current {
            if count.isMultiple(of: 256) { try Task.checkCancellation() }
            let next = iterator.next()
            let after = next?.location ?? last.location
            add(point, tangent: atan2(after.y - previous.y, after.x - previous.x), previousEdges: &edges, to: coverage)
            previous = point.location
            current = next
            count += 1
        }
        if count == 0 || previous != last.location {
            add(last, tangent: atan2(last.location.y - previous.y, last.location.x - previous.x), previousEdges: &edges, to: coverage)
        }
        context.setFillColor(color.cgColor)
        context.addPath(coverage.normalized())
        context.fillPath()
    }

    private static func add(_ point: PKStrokePoint, tangent: CGFloat,
                            previousEdges: inout (CGPoint, CGPoint)?, to coverage: CGMutablePath) {
        // Exclude native stamp padding; the pixel fixtures guard this coverage approximation.
        let radiusX = max(0, point.size.height - 2)
        let radiusY = max(0, point.size.width - 2)
        guard radiusX > 0, radiusY > 0 else {
            previousEdges = nil
            return
        }
        let offset = CGPoint(x: sin(tangent) * radiusY, y: -cos(tangent) * radiusY)
        let edges = (CGPoint(x: point.location.x + offset.x, y: point.location.y + offset.y),
                     CGPoint(x: point.location.x - offset.x, y: point.location.y - offset.y))
        // Join samples so hairlines stay continuous even when narrower than the sampling stride.
        if let previousEdges {
            coverage.move(to: previousEdges.0)
            coverage.addLine(to: edges.0)
            coverage.addLine(to: edges.1)
            coverage.addLine(to: previousEdges.1)
            coverage.closeSubpath()
        }
        previousEdges = edges
        let nib = CGRect(x: -radiusX, y: -radiusY, width: 2 * radiusX, height: 2 * radiusY)
        let transform = CGAffineTransform(translationX: point.location.x, y: point.location.y).rotated(by: tangent)
        coverage.addEllipse(in: nib, transform: transform)
    }

    // The native marker shader is private; fit broad-nib coverage to the pixel fixtures.
    private static func drawMarker(_ stroke: PKStroke, color: UIColor, in context: CGContext) throws {
        var parameter: CGFloat = 0
        let end = CGFloat(stroke.path.count - 1)
        repeat {
            try Task.checkCancellation()
            let point = stroke.path.interpolatedPoint(at: parameter)
            let width = max(0.1, point.size.height * 1.5)
            let height = max(0.1, point.size.width * 0.5)
            context.saveGState()
            context.translateBy(x: point.location.x, y: point.location.y)
            context.rotate(by: point.azimuth)
            let nib = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            context.addPath(CGPath(roundedRect: nib, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
            if stroke.path.count == 1 {
                // An isolated dab uses mean pigment density instead of the native randomized grain.
                let alpha = min(1, max(0, point.opacity * 0.4)) * color.cgColor.alpha
                context.setFillColor(color.withAlphaComponent(alpha).cgColor)
                context.fillPath()
            } else {
                context.clip()
                context.setFillColor(color.withAlphaComponent(1).cgColor)
                context.setShouldAntialias(false)
                // Disjoint bands preserve varying alpha in PDF without rasterizing a gradient mask.
                for band in 0..<32 {
                    let density = 0.65 * (0.23 + 0.77 * (CGFloat(band) + 0.5) / 32)
                    context.setAlpha(min(1, max(0, point.opacity * density)) * color.cgColor.alpha)
                    context.fill(CGRect(x: nib.minX, y: nib.minY + height * CGFloat(band) / 32,
                                        width: width, height: height / 32))
                }
            }
            context.restoreGState()
            if parameter == end { break }
            let next = stroke.path.parametricValue(parameter, offsetBy: .distance(max(0.25, point.size.width * 0.15)))
            parameter = next.isFinite && next > parameter ? min(end, next) : end
        } while parameter <= end
    }
}
