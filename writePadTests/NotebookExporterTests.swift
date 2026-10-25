import PDFKit
import PencilKit
import Testing
import UIKit
@testable import writePad

@MainActor
struct NotebookExporterTests {
    let store: NotebookStore

    init() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
    }

    @Test func pdfPreservesPageOrderPaperAndUnsavedInk() async throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.addPage()
        editor.setBackground(.grid, forPageAt: 0)
        editor.movePages(from: [1], to: 0)
        let layout = PageLayout(pageCount: 2)
        editor.drawingDidChange(layout.merge([
            PKDrawing(strokes: [PageLayoutTests.stroke(at: CGPoint(x: 100, y: 100))]), PKDrawing(),
        ]))

        let url = try await editor.export(as: .pdf, directory: store.rootURL)
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount == 2)
        let first = try #require(pdf.page(at: 0))
        let second = try #require(pdf.page(at: 1))
        #expect(first.bounds(for: .mediaBox).size == PageLayout.pageSize)
        #expect(isDark(pixel(first.thumbnail(of: PageLayout.pageSize, for: .mediaBox), x: 100, y: 100)))
        #expect(!isDark(pixel(second.thumbnail(of: PageLayout.pageSize, for: .mediaBox), x: 100, y: 100)))
        #expect(pixel(second.thumbnail(of: PageLayout.pageSize, for: .mediaBox), x: 24, y: 200)[0] < 230)
        #expect(first.annotations.isEmpty)
    }

    @Test func pngContainsPaperAndInkWithWhitePaperInDarkMode() throws {
        let page = PageInfo(background: .lined)
        let manifest = NotebookManifest(title: "Notes / Lecture", pages: [page])
        let snapshot = NotebookExport(manifest: manifest,
                                      drawings: [page.id: PKDrawing(strokes: [PageLayoutTests.stroke(at: CGPoint(x: 100, y: 100))])
                                        .dataRepresentation()], sourcePDFURL: store.sourcePDFURL(for: manifest.id))
        var result: Result<URL, Error>!
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            result = Result { try NotebookExporter.export(snapshot, as: .png(pageID: page.id), directory: store.rootURL) }
        }
        let url = try result.get()
        let image = try #require(UIImage(data: Data(contentsOf: url)))
        #expect(image.cgImage?.width == 1588)
        #expect(image.cgImage?.height == 2246)
        #expect(pixel(image, x: 10, y: 10).prefix(3).allSatisfy { $0 > 250 })
        #expect(isDark(pixel(image, x: 200, y: 200)))
        #expect(pixel(image, x: 400, y: 192)[0] < 230)
        #expect(url.lastPathComponent == "Notes - Lecture - Page 1.png")
    }

    @Test(arguments: [0, 90, 180, 270])
    func pdfSourceCropRotationAndAnnotationsAreFlattened(rotation: Int) throws {
        let source = try makeSourcePDF(rotation: rotation)
        let sourceURL = store.rootURL.appending(path: "source.pdf")
        try #require(source.dataRepresentation()).write(to: sourceURL, options: .atomic)
        let page = PageInfo(pdfPageIndex: 0)
        let manifest = NotebookManifest(title: "Annotated", pages: [page])
        let snapshot = NotebookExport(manifest: manifest, drawings: [:], sourcePDFURL: sourceURL)
        let url = try NotebookExporter.export(snapshot, as: .pdf, directory: store.rootURL)
        let outputDocument = try #require(PDFDocument(url: url))
        let output = try #require(outputDocument.page(at: 0))
        let size = rotation % 180 == 0 ? CGSize(width: 160, height: 240) : CGSize(width: 240, height: 160)
        #expect(output.bounds(for: .mediaBox).size == size)
        #expect(output.annotations.isEmpty)
        let expected = try #require(source.page(at: 0)).thumbnail(of: size, for: .cropBox)
        let actual = output.thumbnail(of: size, for: .mediaBox)
        for y in stride(from: 10, to: Int(size.height), by: 20) {
            for x in stride(from: 10, to: Int(size.width), by: 20) {
                let before = pixel(expected, x: x, y: y)
                let after = pixel(actual, x: x, y: y)
                #expect(zip(before.prefix(3), after.prefix(3)).allSatisfy { abs(Int($0) - Int($1)) < 15 })
            }
        }
    }

    @Test func mixedPDFAndInsertedPaperFollowManifestOrder() throws {
        let sourceURL = store.rootURL.appending(path: "source.pdf")
        try #require(makeSourcePDF().dataRepresentation()).write(to: sourceURL, options: .atomic)
        let manifest = NotebookManifest(title: "Mixed", pages: [PageInfo(background: .dotted), PageInfo(pdfPageIndex: 0)])
        let snapshot = NotebookExport(manifest: manifest, drawings: [:], sourcePDFURL: sourceURL)
        let url = try NotebookExporter.export(snapshot, as: .pdf, directory: store.rootURL)
        let output = try #require(PDFDocument(url: url))
        #expect(output.pageCount == 2)
        #expect(output.page(at: 0)?.bounds(for: .mediaBox).size == PageLayout.pageSize)
        #expect(output.page(at: 1)?.bounds(for: .mediaBox).size == CGSize(width: 160, height: 240))
    }

    @Test(arguments: [0, 90, 180, 270])
    func unsavedPDFMarkupsAreFlattenedAtTheCorrectCoordinates(rotation: Int) throws {
        let source = try makeSourcePDF(rotation: rotation)
        let sourceURL = store.rootURL.appending(path: "source.pdf")
        try #require(source.dataRepresentation()).write(to: sourceURL, options: .atomic)
        let page = PageInfo(pdfPageIndex: 0)
        let markup = PDFMarkup(pageID: page.id, kind: .highlight, bounds: CGRect(x: 35, y: 70, width: 70, height: 40))
        let snapshot = NotebookExport(manifest: NotebookManifest(title: "Markup", pages: [page]),
                                      drawings: [:], sourcePDFURL: sourceURL, markups: [markup])
        let url = try NotebookExporter.export(snapshot, as: .pdf, directory: store.rootURL)
        let output = try #require(PDFDocument(url: url))
        let rendered = try #require(output.page(at: 0))
        #expect(rendered.annotations.isEmpty)
        let original = try #require(source.page(at: 0))
        original.addAnnotation(markup.annotation())
        let size = rendered.bounds(for: .mediaBox).size
        let expected = original.thumbnail(of: size, for: .cropBox)
        let actual = rendered.thumbnail(of: size, for: .mediaBox)
        for y in stride(from: 10, to: Int(size.height), by: 20) {
            for x in stride(from: 10, to: Int(size.width), by: 20) {
                #expect(zip(pixel(expected, x: x, y: y).prefix(3), pixel(actual, x: x, y: y).prefix(3))
                    .allSatisfy { abs(Int($0) - Int($1)) < 15 })
            }
        }
    }

    @Test func insertedPageCommentAppearsInPNGExport() throws {
        let page = PageInfo()
        let markup = PDFMarkup(pageID: page.id, kind: .comment, bounds: CGRect(x: 30, y: 1000, width: 24, height: 24), text: "Note")
        let snapshot = NotebookExport(manifest: NotebookManifest(title: "Blank comment", pages: [page]),
                                      drawings: [:], sourcePDFURL: store.rootURL.appending(path: "missing.pdf"), markups: [markup])
        let url = try NotebookExporter.export(snapshot, as: .png(pageID: page.id), directory: store.rootURL)
        let image = try #require(UIImage(data: Data(contentsOf: url)))
        let colors = stride(from: 62, to: 106, by: 4).flatMap { x in
            stride(from: 202, to: 246, by: 4).map { y in pixel(image, x: x, y: y) }
        }
        #expect(colors.contains { $0[2] < 150 })
    }

    @Test func missingPDFAndDeletedPageFailInsteadOfExportingBlankPaper() throws {
        let page = PageInfo(pdfPageIndex: 0)
        let manifest = NotebookManifest(title: "Missing", pages: [page])
        let snapshot = NotebookExport(manifest: manifest, drawings: [:], sourcePDFURL: store.sourcePDFURL(for: manifest.id))
        #expect(throws: NotebookExporter.ExportError.self) {
            try NotebookExporter.export(snapshot, as: .pdf, directory: store.rootURL)
        }
        let notebook = NotebookExport(manifest: NotebookManifest(title: "Notes"), drawings: [:], sourcePDFURL: snapshot.sourcePDFURL)
        #expect(throws: NotebookExporter.ExportError.self) {
            try NotebookExporter.export(notebook, as: .png(pageID: UUID()), directory: store.rootURL)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path(percentEncoded: false)).isEmpty)
    }

    @Test func corruptDrawingLeavesNoPartialExport() throws {
        let page = PageInfo()
        let manifest = NotebookManifest(title: "Broken ink", pages: [page])
        let snapshot = NotebookExport(manifest: manifest, drawings: [page.id: Data([1, 2, 3])],
                                      sourcePDFURL: store.sourcePDFURL(for: manifest.id))
        #expect(throws: (any Error).self) {
            try NotebookExporter.export(snapshot, as: .pdf, directory: store.rootURL)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path(percentEncoded: false)).isEmpty)
    }

    @Test func exportingInsertedBlankPageDoesNotRequireOriginalPDF() throws {
        let paper = PageInfo(background: .grid)
        let manifest = NotebookManifest(title: "Inserted", pages: [PageInfo(pdfPageIndex: 0), paper])
        let snapshot = NotebookExport(manifest: manifest, drawings: [:], sourcePDFURL: store.sourcePDFURL(for: manifest.id))
        let url = try NotebookExporter.export(snapshot, as: .png(pageID: paper.id), directory: store.rootURL)
        #expect(UIImage(data: try Data(contentsOf: url))?.cgImage?.width == 1588)
        #expect(url.lastPathComponent == "Inserted - Page 2.png")
    }

    @Test func longNotebookExportsEveryPage() throws {
        let manifest = NotebookManifest(title: "Long notebook", pages: (0..<101).map { _ in PageInfo(background: .lined) })
        let snapshot = NotebookExport(manifest: manifest, drawings: [:], sourcePDFURL: store.sourcePDFURL(for: manifest.id))
        let url = try NotebookExporter.export(snapshot, as: .pdf, directory: store.rootURL)
        #expect(PDFDocument(url: url)?.pageCount == 101)
    }

    @Test(arguments: [PageBackground.cornell, .music, .plannerWeek])
    func pageTemplatesAppearInThumbnailsPDFAndPNG(background: PageBackground) throws {
        let page = PageInfo(background: background)
        let manifest = NotebookManifest(title: background.rawValue, pages: [page])
        let snapshot = NotebookExport(manifest: manifest, drawings: [:], sourcePDFURL: store.sourcePDFURL(for: manifest.id))
        let point: CGPoint
        switch background {
        case .cornell: point = CGPoint(x: PageLayout.pageSize.width * 0.25, y: 200)
        case .music: point = CGPoint(x: 200, y: 48)
        default: point = CGPoint(x: 200, y: 40)
        }
        let pdfURL = try NotebookExporter.export(snapshot, as: .pdf, directory: store.rootURL)
        let document = try #require(PDFDocument(url: pdfURL))
        let pdfPage = try #require(document.page(at: 0))
        let pngURL = try NotebookExporter.export(snapshot, as: .png(pageID: page.id), directory: store.rootURL)
        let images = [
            PageBackgroundRenderer.thumbnail(background: background, drawing: PKDrawing(), width: 140),
            pdfPage.thumbnail(of: PageLayout.pageSize, for: .mediaBox),
            try #require(UIImage(contentsOfFile: pngURL.path(percentEncoded: false))),
        ]
        for image in images {
            let scale = CGFloat(try #require(image.cgImage).width) / PageLayout.pageSize.width
            let x = Int(point.x * scale)
            let y = Int(point.y * scale)
            // Sample a small neighborhood to allow antialiasing at each renderer's scale.
            let red = (-2...2).flatMap { dx in
                (-2...2).map { dy in pixel(image, x: x + dx, y: y + dy)[0] }
            }
            #expect(try #require(red.min()) < 230)
            #expect(pixel(image, x: Int(10 * scale), y: Int(10 * scale)).prefix(3).allSatisfy { $0 > 250 })
        }
    }

    private func makeSourcePDF(rotation: Int = 0) throws -> PDFDocument {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300)).pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.red.setFill()
            context.fill(CGRect(x: 20, y: 30, width: 60, height: 80))
            UIColor.green.setFill()
            context.fill(CGRect(x: 100, y: 150, width: 80, height: 120))
        }
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        page.setBounds(CGRect(x: 20, y: 30, width: 160, height: 240), for: .cropBox)
        page.rotation = rotation
        let annotation = PDFAnnotation(bounds: CGRect(x: 60, y: 120, width: 60, height: 40), forType: .square, withProperties: nil)
        annotation.color = .blue
        annotation.interiorColor = .blue
        page.addAnnotation(annotation)
        return document
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in
            image.draw(in: CGRect(x: -x, y: -y, width: image.cgImage!.width, height: image.cgImage!.height))
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(sample.cgImage!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }

    private func isDark(_ pixel: [UInt8]) -> Bool { pixel.prefix(3).allSatisfy { $0 < 80 } }
}

extension NotebookExporterTests {
    @Test(arguments: [0, 90, 180, 270])
    func pageItemsRenderOverRotatedPDFWithoutChangingSource(rotation: Int) async throws {
        let sourceURL = store.rootURL.appending(path: "items.pdf")
        let source = try #require(makeSourcePDF(rotation: rotation).dataRepresentation())
        try source.write(to: sourceURL)
        let manifest = try store.importPDF(from: sourceURL, title: "PDF Items")
        let editor = try EditorViewModel(store: store, manifest: manifest)
        try await checkItemsRender(editor)
        #expect(try Data(contentsOf: store.sourcePDFURL(for: manifest.id)) == source)
    }

    @Test func pageItemsRenderInPaperExportsAndBothThumbnails() async throws {
        try await checkItemsRender(EditorViewModel.openDefault(store: store))
    }

    private func checkItemsRender(_ editor: EditorViewModel) async throws {
        let id = editor.pages[0].id
        editor.addText("Hello page items", to: id)
        let asset = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 30)).pngData { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 30))
        }
        try editor.addImage(asset, to: id)
        var imageItem = try #require(editor.selectedItem)
        imageItem.frame = CGRect(x: 20, y: 20, width: 60, height: 30)
        editor.updateItem(imageItem, on: id)
        let pngURL = try await editor.export(as: .png(pageID: id), directory: store.rootURL)
        let pdfURL = try await editor.export(as: .pdf, directory: store.rootURL)
        let output = try #require(PDFDocument(url: pdfURL))
        let page = try #require(output.page(at: 0))
        editor.saveNow()
        #expect(editor.lastError == nil)
        await editor.waitForThumbnails()
        let library = try #require(await PageThumbnailJob.libraryImage(store: store, notebookID: editor.manifest.id))
        let images = [try #require(UIImage(contentsOfFile: pngURL.path)),
                      page.thumbnail(of: editor.pageSize(for: id), for: .mediaBox),
                      try #require(editor.thumbnails[id]), library]
        for image in images {
            let scale = CGFloat(try #require(image.cgImage).width) / editor.pageSize(for: id).width
            let color = pixel(image, x: Int(40 * scale), y: Int(35 * scale))
            #expect(color[0] > 220 && color[1] < 50 && color[2] > 220)
        }
        #expect(page.string?.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ").contains("Hello page items") == true)
    }

}
