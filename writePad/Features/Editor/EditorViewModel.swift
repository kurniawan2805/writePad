import Foundation
import Observation
import PencilKit

@MainActor
@Observable
final class EditorViewModel {
    private(set) var manifest: NotebookManifest
    private(set) var drawing: PKDrawing
    private(set) var lastError: String?
    var allowsFingerDrawing: Bool

    private let store: NotebookStore
    private var pendingSave: Task<Void, Never>?
    private var hasUnsavedChanges = false

    /// Delay after the last stroke before writing to disk.
    static let autosaveDelay: Duration = .seconds(1)

    private var pageID: UUID { manifest.pages[0].id }

    init(store: NotebookStore, manifest: NotebookManifest) {
        self.store = store
        self.manifest = manifest
        self.drawing = (try? store.loadDrawing(pageID: manifest.pages[0].id, notebookID: manifest.id)) ?? PKDrawing()
        #if targetEnvironment(simulator)
        self.allowsFingerDrawing = true // the simulator has no Apple Pencil
        #else
        self.allowsFingerDrawing = false
        #endif
    }

    /// Opens the most recently edited notebook, or creates the first one.
    static func openDefault(store: NotebookStore = NotebookStore()) throws -> EditorViewModel {
        let manifest = try store.listNotebooks().first ?? store.createNotebook(title: "My Notebook")
        return EditorViewModel(store: store, manifest: manifest)
    }

    func drawingDidChange(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        hasUnsavedChanges = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges else { return }
        do {
            try store.saveDrawing(drawing, pageID: pageID, notebookID: manifest.id)
            manifest.updatedAt = .now
            try store.saveManifest(manifest)
            hasUnsavedChanges = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
