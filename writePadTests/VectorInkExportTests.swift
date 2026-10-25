import PDFKit
import PencilKit
import Testing
import UIKit
@testable import writePad

@MainActor
struct VectorInkExportTests {
    enum Shape: String, CaseIterable {
        case line, curve, dot, ellipse, erased, overlap, faint, thin, hairline, varyingOpacity
    }

    private let rect = CGRect(x: 0, y: 0, width: 240, height: 240)

    @Test(arguments: [PKInk.InkType.pen.rawValue, PKInk.InkType.monoline.rawValue, PKInk.InkType.marker.rawValue], Shape.allCases)
    func vectorPDFMatchesPencilKit(inkName: String, shape: Shape) throws {
        let ink = try #require(PKInk.InkType(rawValue: inkName))
        let drawing = fixture(ink: ink, shape: shape)
        let (actual, images) = try exported(drawing)
        let expected = native(drawing)
        let metrics = try difference(expected, actual)
        print("FIDELITY \(ink) \(shape): \(metrics)")
        if metrics.meanError >= 18 || metrics.edgeAgreement <= 0.95 {
            let folder = URL.temporaryDirectory.appending(path: "T10-QA", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try expected.pngData()?.write(to: folder.appending(path: "\(inkName)-\(shape)-native.png"))
            try actual.pngData()?.write(to: folder.appending(path: "\(inkName)-\(shape)-vector.png"))
            print("IMAGES \(folder.path)")
        }
        #expect(images == 0, "Solid ink must remain vector, including transparency forms")
        #expect(metrics.meanError < 18, "\(ink) \(shape): \(metrics)")
        #expect(metrics.edgeAgreement > 0.95, "\(ink) \(shape): \(metrics)")
    }

    @Test(arguments: [PKInk.InkType.pencil.rawValue, PKInk.InkType.crayon.rawValue,
                      PKInk.InkType.watercolor.rawValue, PKInk.InkType.fountainPen.rawValue])
    func texturedInksKeepNativeRendering(inkName: String) throws {
        let ink = try #require(PKInk.InkType(rawValue: inkName))
        let drawing = fixture(ink: ink, shape: .curve)
        let (actual, images) = try exported(drawing)
        let metrics = try difference(native(drawing), actual)
        print("TEXTURE \(ink): \(metrics)")
        #expect(images > 0)
        #expect(metrics.meanError < 5)
    }

    @Test func mixedInkKeepsStackingOrder() throws {
        let inks: [PKInk.InkType] = [.pen, .pencil, .marker, .crayon, .monoline]
        let strokes = inks.enumerated().map { index, ink in
            stroke(ink: ink, locations: [CGPoint(x: 40, y: 80 + index * 8), CGPoint(x: 200, y: 160 - index * 8)],
                   color: index.isMultiple(of: 2) ? .systemRed : .systemBlue)
        }
        let drawing = PKDrawing(strokes: strokes)
        let (actual, images) = try exported(drawing)
        let metrics = try difference(native(drawing), actual)
        print("MIXED: \(metrics)")
        #expect(images > 0)
        #expect(metrics.meanError < 20)
    }

    @Test(arguments: [PKInk.InkType.pen.rawValue, PKInk.InkType.monoline.rawValue, PKInk.InkType.marker.rawValue])
    func darkAppearanceDoesNotChangePDFInk(inkName: String) throws {
        let ink = try #require(PKInk.InkType(rawValue: inkName))
        let drawing = PKDrawing(strokes: [stroke(ink: ink, locations: [CGPoint(x: 30, y: 60), CGPoint(x: 180, y: 160)],
                                                color: .label)])
        let light = try exported(drawing).0
        var dark: UIImage?
        var failure: Error?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            do { dark = try exported(drawing).0 } catch { failure = error }
        }
        if let failure { throw failure }
        #expect(try rgba(light) == rgba(#require(dark)))
    }

    @Test(arguments: [PKInk.InkType.pen.rawValue, PKInk.InkType.monoline.rawValue, PKInk.InkType.marker.rawValue])
    func separateStrokesKeepTheirTransparencyAndOrder(inkName: String) throws {
        let ink = try #require(PKInk.InkType(rawValue: inkName))
        let drawing = PKDrawing(strokes: [
            stroke(ink: ink, locations: [CGPoint(x: 30, y: 60), CGPoint(x: 200, y: 180)],
                   color: UIColor.systemRed.withAlphaComponent(0.6)),
            stroke(ink: ink, locations: [CGPoint(x: 30, y: 180), CGPoint(x: 200, y: 60)],
                   color: UIColor.systemBlue.withAlphaComponent(0.6)),
        ])
        let (actual, images) = try exported(drawing)
        let metrics = try difference(native(drawing), actual)
        print("OVERLAP \(ink): \(metrics)")
        #expect(images == 0)
        #expect(metrics.meanError < 18)
        #expect(metrics.edgeAgreement > 0.95)
    }

    @Test(arguments: [PKInk.InkType.pen.rawValue, PKInk.InkType.monoline.rawValue])
    func hairlinesRemainContinuousAtEightTimesZoom(inkName: String) throws {
        let ink = try #require(PKInk.InkType(rawValue: inkName))
        let (image, images) = try exported(fixture(ink: ink, shape: .hairline), scale: 8)
        let width = try #require(image.cgImage).width
        let bytes = try rgba(image)
        let red = (40 * 8..<190 * 8).map { bytes[(100 * 8 * width + $0) * 4] }
        #expect(images == 0)
        print("HAIRLINE \(ink): center red range \(red.min() ?? 255)...\(red.max() ?? 255)")
        #expect(red.allSatisfy { $0 < 100 }, "The center of a fine line must have no gaps")
    }

    private func fixture(ink: PKInk.InkType, shape: Shape) -> PKDrawing {
        let locations: [CGPoint]
        switch shape {
        case .dot: locations = [CGPoint(x: 120, y: 120)]
        case .curve, .ellipse, .faint, .varyingOpacity:
            locations = (0..<41).map { index in
                CGPoint(x: 30 + CGFloat(index) * 4, y: 100 + sin(CGFloat(index) / 6) * 35)
            }
        case .overlap:
            locations = (0..<81).map { index in
                let angle = CGFloat(index) * .pi / 40
                return CGPoint(x: 120 + 70 * sin(angle), y: 110 + 50 * sin(angle * 2))
            }
        default: locations = [CGPoint(x: 30, y: 100), CGPoint(x: 200, y: 100)]
        }
        let mask: UIBezierPath?
        if shape == .erased {
            mask = UIBezierPath(rect: rect)
            mask?.append(UIBezierPath(rect: CGRect(x: 90, y: 60, width: 30, height: 80)))
            mask?.usesEvenOddFillRule = true
        } else { mask = nil }
        let transform = shape == .erased ? CGAffineTransform(a: 0.9, b: 0.2, c: -0.15, d: 1.1, tx: 20, ty: 10) : .identity
        let points = locations.enumerated().map { index, location in
            let width: CGFloat = shape == .curve ? 4 + CGFloat(index) / 8 : (shape == .thin ? 3 : (shape == .hairline ? 2.125 : 8))
            let size = CGSize(width: width, height: shape == .ellipse ? 14 : width)
            return PKStrokePoint(location: location, timeOffset: Double(index) * 0.01, size: size,
                                 opacity: shape == .faint ? 0.25 : (shape == .varyingOpacity ? 0.1 + CGFloat(index) / 40 : 1), force: 1,
                                 azimuth: shape == .ellipse ? CGFloat(index) / 20 : 0, altitude: .pi / 2)
        }
        let color = shape == .faint ? UIColor.systemBlue.withAlphaComponent(0.4) : .systemBlue
        let first = PKStroke(ink: PKInk(ink, color: color), path: PKStrokePath(controlPoints: points, creationDate: .now),
                             transform: transform, mask: mask, randomSeed: 42)
        return PKDrawing(strokes: [first])
    }

    private func stroke(ink: PKInk.InkType, locations: [CGPoint], color: UIColor) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.01, size: CGSize(width: 8, height: 8),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(ink, color: color), path: PKStrokePath(controlPoints: points, creationDate: .now), randomSeed: 42)
    }

}

extension VectorInkExportTests {
    private func exported(_ drawing: PKDrawing, scale: CGFloat = 2) throws -> (UIImage, Int) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = PageInfo()
        let snapshot = NotebookExport(manifest: NotebookManifest(title: "Vector", pages: [page]),
                                      drawings: [page.id: drawing.dataRepresentation()], sourcePDFURL: root.appending(path: "absent.pdf"))
        let url = try NotebookExporter.export(snapshot, as: .pdf, directory: root)
        let pdf = try #require(CGPDFDocument(url as CFURL))
        let source = try #require(pdf.page(at: 1))
        let image = renderer(scale: scale).image { context in
            context.cgContext.translateBy(x: 0, y: PageLayout.pageSize.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            context.cgContext.drawPDFPage(source)
        }
        return (image, imageCount(try #require(source.dictionary)))
    }

    private func imageCount(_ dictionary: CGPDFDictionaryRef) -> Int {
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return 0 }
        var visited: Set<UInt> = []
        return imageCount(in: resources, visited: &visited)
    }

    private func imageCount(in dictionary: CGPDFDictionaryRef, visited: inout Set<UInt>) -> Int {
        guard visited.insert(UInt(bitPattern: dictionary.rawValue)).inserted else { return 0 }
        var subtype: UnsafePointer<CChar>?
        var count = 0
        if CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" {
            count += 1
        }
        CGPDFDictionaryApplyBlock(dictionary, { _, object, _ in
            count += imageCount(in: object, visited: &visited)
            return true
        }, nil)
        return count
    }

    private func imageCount(in object: CGPDFObjectRef, visited: inout Set<UInt>) -> Int {
        switch CGPDFObjectGetType(object) {
        case .dictionary:
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { return 0 }
            return imageCount(in: dictionary, visited: &visited)
        case .stream:
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else { return 0 }
            return imageCount(in: dictionary, visited: &visited)
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array else { return 0 }
            var count = 0
            for index in 0..<CGPDFArrayGetCount(array) {
                var element: CGPDFObjectRef?
                if CGPDFArrayGetObject(array, index, &element), let element {
                    count += imageCount(in: element, visited: &visited)
                }
            }
            return count
        default: return 0
        }
    }

    private func native(_ drawing: PKDrawing) -> UIImage {
        renderer().image { context in
            UIColor.white.setFill()
            context.fill(rect)
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                drawing.image(from: rect, scale: 2).draw(in: rect)
            }
        }
    }

    private func renderer(scale: CGFloat = 2) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: rect.size, format: format)
    }

    private struct Metrics: CustomStringConvertible {
        let meanError: Double
        let coverage: Double
        let edgeAgreement: Double
        var description: String { "MAE=\(meanError), IoU=\(coverage), 1px coverage=\(edgeAgreement)" }
    }

    private func difference(_ first: UIImage, _ second: UIImage) throws -> Metrics {
        let before = try rgba(first)
        let after = try rgba(second)
        var error = 0
        var union = 0
        var intersection = 0
        var matched = 0
        var inkCount = 0
        let width = try #require(first.cgImage).width
        let height = try #require(first.cgImage).height
        // Native ink softens edges over about one output pixel; allow that edge displacement only.
        func nearbyInk(_ bytes: [UInt8], at offset: Int) -> Bool {
            let x = (offset / 4) % width
            let y = (offset / 4) / width
            for row in max(0, y - 1)...min(height - 1, y + 1) {
                for column in max(0, x - 1)...min(width - 1, x + 1) {
                    let index = (row * width + column) * 4
                    if bytes[index..<index + 3].contains(where: { $0 < 245 }) { return true }
                }
            }
            return false
        }
        for offset in stride(from: 0, to: before.count, by: 4) {
            let oldInk = before[offset..<offset + 3].contains { $0 < 245 }
            let newInk = after[offset..<offset + 3].contains { $0 < 245 }
            if oldInk || newInk {
                union += 1
                for channel in 0..<3 { error += abs(Int(before[offset + channel]) - Int(after[offset + channel])) }
            }
            if oldInk && newInk { intersection += 1 }
            if oldInk {
                inkCount += 1
                if nearbyInk(after, at: offset) { matched += 1 }
            }
            if newInk {
                inkCount += 1
                if nearbyInk(before, at: offset) { matched += 1 }
            }
        }
        #expect(union > 0, "The fixture must have visible ink")
        return Metrics(meanError: Double(error) / Double(max(1, union * 3)),
                       coverage: Double(intersection) / Double(max(1, union)),
                       edgeAgreement: Double(matched) / Double(max(1, inkCount)))
    }

    private func rgba(_ image: UIImage) throws -> [UInt8] {
        let image = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
