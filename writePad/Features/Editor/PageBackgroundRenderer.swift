import PDFKit
import PencilKit
import UIKit

extension PageBackground {
    var title: String {
        switch self {
        case .blank: "Blank"
        case .lined: "Lined"
        case .grid: "Grid"
        case .dotted: "Dotted"
        case .cornell: "Cornell"
        case .music: "Music Staff"
        case .plannerWeek: "Weekly Planner"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "doc"
        case .lined: "line.3.horizontal"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        case .cornell: "rectangle.lefthalf.inset.filled"
        case .music: "music.note.list"
        case .plannerWeek: "calendar"
        }
    }
}

/// Paper patterns as vector paths in page coordinates, shared by the live canvas and thumbnails.
enum PageBackgroundRenderer {
    static let lineColor = UIColor(red: 0.62, green: 0.71, blue: 0.82, alpha: 1)
    static func lineWidth(for background: PageBackground) -> CGFloat {
        background == .plannerWeek ? 1 : 0.75
    }

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
        case .blank: break
        case .lined: addRuling(to: path, size: size)
        case .grid: addGrid(to: path, size: size)
        case .dotted: addDots(to: path, size: size, radius: dotRadius)
        case .cornell: addCornell(to: path, size: size)
        case .music: addMusic(to: path, size: size)
        case .plannerWeek: addPlannerWeek(to: path, size: size)
        }
        return path
    }

    private static func addRuling(to path: CGMutablePath, size: CGSize) {
        for y in stride(from: 3 * lineSpacing, to: size.height - lineSpacing, by: lineSpacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
    }

    private static func addGrid(to path: CGMutablePath, size: CGSize) {
        for x in stride(from: gridSpacing, to: size.width, by: gridSpacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: gridSpacing, to: size.height, by: gridSpacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
    }

    private static func addDots(to path: CGMutablePath, size: CGSize, radius: CGFloat) {
        for x in stride(from: gridSpacing, to: size.width, by: gridSpacing) {
            for y in stride(from: gridSpacing, to: size.height, by: gridSpacing) {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
            }
        }
    }

    private static func addCornell(to path: CGMutablePath, size: CGSize) {
        let cue = size.width * 0.25
        let summary = size.height * 0.8
        path.move(to: CGPoint(x: cue, y: 0))
        path.addLine(to: CGPoint(x: cue, y: summary))
        path.move(to: CGPoint(x: 0, y: summary))
        path.addLine(to: CGPoint(x: size.width, y: summary))
        for y in stride(from: lineSpacing, to: summary, by: lineSpacing) {
            path.move(to: CGPoint(x: cue, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
    }

    private static func addMusic(to path: CGMutablePath, size: CGSize) {
        for staff in 0..<10 {
            for line in 0..<5 {
                let y = CGFloat(48 + staff * 72 + line * 8)
                guard y <= size.height - 48 else { continue }
                path.move(to: CGPoint(x: 48, y: y))
                path.addLine(to: CGPoint(x: size.width - 48, y: y))
            }
        }
    }

    private static func addPlannerWeek(to path: CGMutablePath, size: CGSize) {
        let rowHeight = size.height / 7
        for row in 0..<7 {
            let top = CGFloat(row) * rowHeight
            path.move(to: CGPoint(x: 0, y: top + min(40, rowHeight)))
            path.addLine(to: CGPoint(x: size.width, y: top + min(40, rowHeight)))
            if row > 0 {
                path.move(to: CGPoint(x: 0, y: top))
                path.addLine(to: CGPoint(x: size.width, y: top))
            }
        }
    }

    /// A PDF page with its page-local ink, sized to the page's displayed (cropped, rotated) shape.
    static func thumbnail(pdfPage: PDFPage, drawing: PKDrawing, width: CGFloat) -> UIImage {
        let size = PDFPageCanvas.displaySize(for: pdfPage)
        let target = CGSize(width: width, height: width * size.height / size.width)
        let page = pdfPage.thumbnail(of: target, for: .cropBox)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: CGRect(origin: .zero, size: size), scale: 2 * width / size.width)
        }
        return UIGraphicsImageRenderer(size: target).image { _ in
            page.draw(in: CGRect(origin: .zero, size: target))
            ink.draw(in: CGRect(origin: .zero, size: target))
        }
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
