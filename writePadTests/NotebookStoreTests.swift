import Foundation
import PencilKit
import Testing
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

    @Test func newerFormatVersionIsRejected() throws {
        var manifest = try store.createNotebook(title: "Future")
        manifest.version = NotebookManifest.currentVersion + 1
        try store.saveManifest(manifest)

        #expect(throws: NotebookStore.StoreError.unsupportedVersion(manifest.version)) {
            try store.loadManifest(id: manifest.id)
        }
    }

    @MainActor
    @Test func editorSavesDrawingAndReopens() throws {
        let editor = try EditorViewModel.openDefault(store: store)
        editor.drawingDidChange(Self.sampleDrawing())
        editor.saveNow()

        let reopened = try EditorViewModel.openDefault(store: store)
        #expect(reopened.manifest.id == editor.manifest.id)
        #expect(reopened.drawing.strokes.count == 1)
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
