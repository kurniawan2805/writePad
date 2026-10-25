import Foundation
import PencilKit
import Testing
import UIKit
@testable import writePad

struct NotebookStoreTests {
    let store: NotebookStore

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
    }

    @Test func createdNotebookIsListed() throws {
        let manifest = try store.createNotebook(title: "Physics")
        let listed = try store.listNotebooks()
        #expect(listed.map(\.id) == [manifest.id])
        #expect(listed.first?.title == "Physics")
        #expect(listed.first?.pages.count == 1)
    }

    @Test func unsavedPageLoadsEmptyDrawing() throws {
        let manifest = try store.createNotebook(title: "Empty")
        let drawing = try store.loadDrawing(pageID: manifest.pages[0].id, notebookID: manifest.id)
        #expect(drawing.strokes.isEmpty)
    }

    @Test func drawingRoundTrips() throws {
        let manifest = try store.createNotebook(title: "Math")
        let pageID = manifest.pages[0].id
        let drawing = Self.sampleDrawing()

        try store.saveDrawing(drawing, pageID: pageID, notebookID: manifest.id)
        let loaded = try store.loadDrawing(pageID: pageID, notebookID: manifest.id)

        #expect(loaded.strokes.count == 1)
        #expect(loaded.strokes[0].path.count == drawing.strokes[0].path.count)
        #expect(loaded.bounds == drawing.bounds)
    }

    @Test @MainActor func importingPDFCopiesSourceAndMapsItsPages() throws {
        let sourceURL = store.rootURL.appending(path: "Lecture.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let pdfData = renderer.pdfData { context in
            context.beginPage()
            context.beginPage()
        }
        try pdfData.write(to: sourceURL)

        let manifest = try store.importPDF(from: sourceURL, title: "Lecture")

        #expect(manifest.version == NotebookManifest.currentVersion)
        #expect(manifest.pages.map(\.pdfPageIndex) == [0, 1])
        #expect(try Data(contentsOf: store.sourcePDFURL(for: manifest.id)) == pdfData)
        #expect(try store.loadManifest(id: manifest.id).title == manifest.title)
    }

    @Test func invalidPDFDoesNotLeaveAPackage() throws {
        let sourceURL = store.rootURL.appending(path: "broken.pdf")
        try Data("not a PDF".utf8).write(to: sourceURL)

        #expect(throws: NotebookStore.StoreError.invalidPDF) {
            try store.importPDF(from: sourceURL, title: "Broken")
        }
        #expect(try store.listNotebooks().isEmpty)
    }

    @Test func versionOneManifestWithoutPDFPageIndexStillLoads() throws {
        let notebookID = UUID()
        let pageID = UUID()
        let packageURL = store.packageURL(for: notebookID)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifestJSON = """
        {
            "createdAt": "2024-01-01T00:00:00.000Z",
            "id": "\(notebookID.uuidString)",
            "pages": [{"background": "blank", "id": "\(pageID.uuidString)"}],
            "title": "Legacy",
            "updatedAt": "2024-01-01T00:00:00.000Z",
            "version": 1
        }
        """
        try Data(manifestJSON.utf8).write(to: packageURL.appending(path: "manifest.json"))

        let manifest = try store.loadManifest(id: notebookID)

        #expect(manifest.version == 1)
        #expect(manifest.pages.first?.pdfPageIndex == nil)
    }

    @Test func deletingMissingDrawingIsNoOp() throws {
        let manifest = try store.createNotebook(title: "Nothing")
        try store.deleteDrawing(pageID: UUID(), notebookID: manifest.id)
    }

    @Test func rootFolderWithSpacesListsAndLoadsNotebooks() throws {
        let root = store.rootURL.appending(path: "Application Support/Note Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let spaced = NotebookStore(rootURL: root)
        let manifest = try spaced.createNotebook(title: "Spaced")
        try spaced.saveDrawing(Self.sampleDrawing(), pageID: manifest.pages[0].id, notebookID: manifest.id)

        #expect(try spaced.listNotebooks().map(\.id) == [manifest.id])
        #expect(try spaced.loadDrawing(pageID: manifest.pages[0].id, notebookID: manifest.id).strokes.count == 1)
    }

    @Test func newerFormatVersionIsRejected() throws {
        var manifest = try store.createNotebook(title: "Future")
        manifest.version = NotebookManifest.currentVersion + 1
        try store.saveManifest(manifest)

        #expect(throws: NotebookStore.StoreError.unsupportedVersion(manifest.version)) {
            try store.loadManifest(id: manifest.id)
        }
    }

    static func sampleDrawing() -> PKDrawing {
        let points = (0..<10).map { index in
            PKStrokePoint(location: CGPoint(x: index * 10, y: index * 5), timeOffset: TimeInterval(index) * 0.01,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
        return PKDrawing(strokes: [stroke])
    }
}
