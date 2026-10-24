import PencilKit
import UIKit

extension PageBackground {
    var title: String {
        switch self {
        case .blank: "Blank"
        case .lined: "Lined"
        case .grid: "Grid"
        case .dotted: "Dotted"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "doc"
        case .lined: "line.3.horizontal"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        }
    }
}

/// Paper patterns as vector paths in page coordinates, shared by the live canvas and thumbnails.
enum PageBackgroundRenderer {
    static let lineColor = UIColor(red: 0.62, green: 0.71, blue: 0.82, alpha: 1)
    static let lineWidth: CGFloat = 0.75

    private static let lineSpacing: CGFloat = 32
    private static let gridSpacing: CGFloat = 24
    private static let dotRadius: CGFloat = 1.2

    /// Whether the pattern path should be filled (dots) rather than stroked (lines).
    static func isFilled(_ background: PageBackground) -> Bool {
        background == .dotted
    }

    static func patternPath(
        for background: PageBackground,
        size: CGSize = PageLayout.pageSize,
        dotRadius: CGFloat = dotRadius
    ) -> CGPath {
        let path = CGMutablePath()
        switch background {
        case .blank:
            break
        case .lined:
            for y in stride(from: 3 * lineSpacing, to: size.height - lineSpacing, by: lineSpacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        case .grid:
            for x in stride(from: gridSpacing, to: size.width, by: gridSpacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: gridSpacing, to: size.height, by: gridSpacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        case .dotted:
            for x in stride(from: gridSpacing, to: size.width, by: gridSpacing) {
                for y in stride(from: gridSpacing, to: size.height, by: gridSpacing) {
                    path.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
                }
            }
        }
        return path
    }

    static func thumbnail(background: PageBackground, drawing: PKDrawing, width: CGFloat) -> UIImage {
        let pageRect = CGRect(origin: .zero, size: PageLayout.pageSize)
        let scale = width / pageRect.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: pageRect.height * scale), format: format)

        // Paper is always white, so render ink with light-mode colors.
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: pageRect, scale: scale * format.scale)
        }

        return renderer.image { context in
            let graphics = context.cgContext
            UIColor.white.setFill()
            graphics.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))
            graphics.scaleBy(x: scale, y: scale)
            // Enlarge dots so they survive downscaling (~1 pt in the thumbnail).
            graphics.addPath(patternPath(for: background, dotRadius: max(dotRadius, 0.6 / scale)))
            if isFilled(background) {
                graphics.setFillColor(lineColor.cgColor)
                graphics.fillPath()
            } else {
                graphics.setStrokeColor(lineColor.cgColor)
                graphics.setLineWidth(0.5 / scale) // hairline at thumbnail size
                graphics.strokePath()
            }
            ink.draw(in: pageRect)
        }
    }
}
