import PDFKit
import PencilKit
import Testing
import UIKit
@testable import writePad

/// Exported PDFs carry markups as real annotations: comment text survives and other apps can edit highlights.
@MainActor
struct PDFExportAnnotationTests {
    let root: URL

    init() throws {
        root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func commentsKeepTheirTextAndSourceNotesAreNotFlattenedTwice() throws {
        let source = try sourcePDF(rotation: 0)
        let note = PDFAnnotation(bounds: CGRect(x: 40, y: 200, width: 24, height: 24), forType: .text, withProperties: nil)
        note.contents = "From the lecturer"
        source.page(at: 0)?.addAnnotation(note)
        let page = PageInfo(pdfPageIndex: 0)
        let mine = PDFMarkup(pageID: page.id, kind: .comment, bounds: CGRect(x: 120, y: 60, width: 24, height: 24),
                             text: "Ask about this")
        let output = try export(source: source, pages: [page], markups: [mine])
        let notes = try #require(output.page(at: 0)).annotations.filter { $0.type == "Text" }
        #expect(Set(notes.compactMap(\.contents)) == ["From the lecturer", "Ask about this"])
        // Crop origin (20, 30) is removed from the coordinates.
        #expect(notes.first { $0.contents == "Ask about this" }?.bounds.origin == CGPoint(x: 100, y: 30))
        #expect(output.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Annotated")
    }

    @Test(arguments: [PDFMarkup.Kind.highlight, .underline, .strikeOut], [0, 90, 180, 270])
    func markupsAreLiveAnnotationsDrawnWhereTheAppShowsThem(kind: PDFMarkup.Kind, rotation: Int) throws {
        let source = try sourcePDF(rotation: rotation)
        let page = PageInfo(pdfPageIndex: 0)
        let markup = PDFMarkup(pageID: page.id, kind: kind, bounds: CGRect(x: 35, y: 70, width: 70, height: 40), text: "line")
        let output = try export(source: source, pages: [page], markups: [markup])
        let rendered = try #require(output.page(at: 0))
        #expect(rendered.annotations.map(\.type) == [kind.subtype.rawValue.trimmingCharacters(in: ["/"])])
        #expect(rendered.annotations.first?.contents == "line")

        let original = try #require(source.page(at: 0))
        // At 3x a hairline keeps its full color instead of an antialiased tint.
        let size = rendered.bounds(for: .mediaBox).size.applying(CGAffineTransform(scaleX: 3, y: 3))
        let base = try Bitmap(original.thumbnail(of: size, for: .cropBox))
        original.addAnnotation(markup.annotation())
        let shown = try Bitmap(original.thumbnail(of: size, for: .cropBox))
        let exported = try Bitmap(rendered.thumbnail(of: size, for: .mediaBox))
        let onScreen = shown.marks(over: base), inExport = exported.marks(over: base)
        #expect(!inExport.isEmpty)
        // PDFKit draws underlines from rotated quad points a few points further from the text than on screen;
        // a wrong direction or position is far outside 8 pt.
        let stray = inExport.filter { !onScreen.contains(near: $0, radius: 24) }
        let missing = onScreen.filter { !inExport.contains(near: $0, radius: 24) }
        #expect(stray.isEmpty && missing.isEmpty, "\(kind) at \(rotation)°: \(stray.count) stray, \(missing.count) missing")
    }

    @Test func inkUnderAHighlightStaysVisibleAndVector() throws {
        let page = PageInfo()
        let stroke = PageLayoutTests.stroke(at: CGPoint(x: 100, y: 100))
        // Paper pages use PDF space too: the highlight covers the stroke at y = 100 from the top.
        let highlight = PDFMarkup(pageID: page.id, kind: .highlight,
                                  bounds: CGRect(x: 60, y: PageLayout.pageSize.height - 140, width: 120, height: 80))
        let snapshot = NotebookExport(manifest: NotebookManifest(title: "Ink", pages: [page]),
                                      drawings: [page.id: PKDrawing(strokes: [stroke]).dataRepresentation()],
                                      sourcePDFURL: root.appending(path: "absent.pdf"), markups: [highlight])
        let url = try NotebookExporter.export(snapshot, as: .pdf, directory: root)
        let output = try #require(PDFDocument(url: url))
        let rendered = try #require(output.page(at: 0))
        #expect(rendered.annotations.count == 1)
        let image = rendered.thumbnail(of: PageLayout.pageSize, for: .mediaBox)
        #expect(pixel(image, x: 100, y: 100).prefix(3).allSatisfy { $0 < 90 }, "ink stays dark under the highlight")
        #expect(pixel(image, x: 70, y: 70)[2] < 150, "the highlight is yellow around the ink")
        #expect(String(bytes: try Data(contentsOf: url), encoding: .isoLatin1)?.contains("/Image") == false)
    }

    @Test func pngStillFlattensMarkups() throws {
        let source = try sourcePDF(rotation: 0)
        let page = PageInfo(pdfPageIndex: 0)
        let markup = PDFMarkup(pageID: page.id, kind: .highlight, bounds: CGRect(x: 120, y: 200, width: 50, height: 40))
        try #require(source.dataRepresentation()).write(to: root.appending(path: "source.pdf"))
        let snapshot = NotebookExport(manifest: NotebookManifest(title: "PNG", pages: [page]), drawings: [:],
                                      sourcePDFURL: root.appending(path: "source.pdf"), markups: [markup])
        let url = try NotebookExporter.export(snapshot, as: .png(pageID: page.id), directory: root)
        let image = try #require(UIImage(data: Data(contentsOf: url)))
        // Highlight at PDF (120…170, 200…240) → crop-relative top-left (100…150, 30…70), at 2x.
        #expect(pixel(image, x: 250, y: 100)[2] < 150)
    }

    private func export(source: PDFDocument, pages: [PageInfo], markups: [PDFMarkup]) throws -> PDFDocument {
        let sourceURL = root.appending(path: "source.pdf")
        try #require(source.dataRepresentation()).write(to: sourceURL, options: .atomic)
        let snapshot = NotebookExport(manifest: NotebookManifest(title: "Annotated", pages: pages), drawings: [:],
                                      sourcePDFURL: sourceURL, markups: markups)
        return try #require(PDFDocument(url: NotebookExporter.export(snapshot, as: .pdf, directory: root)))
    }

    /// A 200×300 page with text-free colored blocks, cropped to (20, 30, 160, 240).
    private func sourcePDF(rotation: Int) throws -> PDFDocument {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300)).pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 100, y: 150, width: 80, height: 120))
        }
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        page.setBounds(CGRect(x: 20, y: 30, width: 160, height: 240), for: .cropBox)
        page.rotation = rotation
        return document
    }

    /// RGBA pixels of an image at its own pixel size.
    private struct Bitmap {
        let width: Int, height: Int
        private let bytes: [UInt8]

        init(_ image: UIImage) throws {
            let cgImage = try #require(image.cgImage)
            width = cgImage.width
            height = cgImage.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
                          bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                    .draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            }
            self.bytes = bytes
        }

        subscript(x: Int, y: Int) -> [UInt8] { Array(bytes[(y * width + x) * 4..<(y * width + x) * 4 + 3]) }

        /// Pixels that differ clearly from `base`, the same page without the markup.
        func marks(over base: Bitmap) -> Marks {
            var points = Set<Int>()
            for y in 0..<height {
                for x in 0..<width where zip(self[x, y], base[x, y]).contains(where: { abs(Int($0) - Int($1)) > 60 }) {
                    points.insert(y * width + x)
                }
            }
            return Marks(width: width, points: points)
        }
    }

    private struct Marks {
        let width: Int
        let points: Set<Int>

        var isEmpty: Bool { points.isEmpty }

        func filter(_ isIncluded: (CGPoint) -> Bool) -> [CGPoint] {
            points.map { CGPoint(x: $0 % width, y: $0 / width) }.filter(isIncluded)
        }

        func contains(near point: CGPoint, radius: Int) -> Bool {
            for dy in -radius...radius {
                for dx in -radius...radius where points.contains((Int(point.y) + dy) * width + Int(point.x) + dx) {
                    return true
                }
            }
            return false
        }
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8] {
        guard let cgImage = image.cgImage else { return [0, 0, 0, 0] }
        let scale = CGFloat(cgImage.width) / image.size.width
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cgImage, in: CGRect(x: -CGFloat(x) * scale, y: -CGFloat(cgImage.height) + CGFloat(y + 1) * scale,
                                            width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        }
        return bytes
    }
}
