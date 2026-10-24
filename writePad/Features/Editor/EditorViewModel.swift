import Foundation
import Observation
import PencilKit
import UIKit

@MainActor
@Observable
final class EditorViewModel {
    struct ScrollRequest: Equatable {
        let id = UUID()
        let pageIndex: Int
    }

    private(set) var manifest: NotebookManifest
    private(set) var thumbnails: [UUID: UIImage] = [:]
    private(set) var lastError: String?
    /// Bumped whenever pages are added, removed, reordered or restyled, so the canvas rebuilds.
    private(set) var structureVersion = 0
    private(set) var scrollRequest: ScrollRequest?
    private(set) var currentPageIndex = 0
    var allowsFingerDrawing: Bool

    /// Page-local drawings, keyed by page ID. Not observed: it changes on every stroke.
    @ObservationIgnored private var pageDrawings: [UUID: PKDrawing]
    @ObservationIgnored private var dirtyPageIDs: Set<UUID> = []
    @ObservationIgnored private var deletedPageIDs: Set<UUID> = []
    @ObservationIgnored private var isManifestDirty = false
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    private let store: NotebookStore

    /// Delay after the last change before writing to disk.
    static let autosaveDelay: Duration = .seconds(1)
    static let thumbnailWidth: CGFloat = 140

    var pages: [PageInfo] { manifest.pages }
    private var layout: PageLayout { PageLayout(pageCount: pages.count) }

    init(store: NotebookStore, manifest: NotebookManifest) {
        self.store = store
        self.manifest = manifest
        self.pageDrawings = Dictionary(uniqueKeysWithValues: manifest.pages.map { page in
            (page.id, (try? store.loadDrawing(pageID: page.id, notebookID: manifest.id)) ?? PKDrawing())
        })
        #if targetEnvironment(simulator)
        self.allowsFingerDrawing = true // the simulator has no Apple Pencil
        #else
        self.allowsFingerDrawing = false
        #endif
        for page in manifest.pages { refreshThumbnail(for: page.id) }
    }

    /// Opens the most recently edited notebook, or creates the first one.
    static func openDefault(store: NotebookStore = NotebookStore()) throws -> EditorViewModel {
        let manifest = try store.listNotebooks().first ?? store.createNotebook(title: "My Notebook")
        return EditorViewModel(store: store, manifest: manifest)
    }

    // MARK: Ink

    func drawing(forPage id: UUID) -> PKDrawing {
        pageDrawings[id] ?? PKDrawing()
    }

    func combinedDrawing() -> PKDrawing {
        layout.merge(pages.map { drawing(forPage: $0.id) })
    }

    func drawingDidChange(_ combined: PKDrawing) {
        for (page, newDrawing) in zip(pages, layout.split(combined)) where newDrawing != pageDrawings[page.id] {
            pageDrawings[page.id] = newDrawing
            dirtyPageIDs.insert(page.id)
        }
        scheduleSave()
    }

    // MARK: Pages

    func pageDidBecomeVisible(_ index: Int) {
        if currentPageIndex != index { currentPageIndex = index }
    }

    func scrollToPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        currentPageIndex = index
        scrollRequest = ScrollRequest(pageIndex: index)
    }

    /// Inserts a page after `index` (or at the end) using the same paper as its neighbor.
    func addPage(after index: Int? = nil) {
        let insertIndex = min((index ?? pages.count - 1) + 1, pages.count)
        let background = pages[max(insertIndex - 1, 0)].background
        let page = PageInfo(background: background)
        manifest.pages.insert(page, at: insertIndex)
        pageDrawings[page.id] = PKDrawing()
        refreshThumbnail(for: page.id)
        structureDidChange()
        scrollToPage(insertIndex)
    }

    func deletePage(at index: Int) {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        let page = manifest.pages.remove(at: index)
        pageDrawings[page.id] = nil
        thumbnails[page.id] = nil
        dirtyPageIDs.remove(page.id)
        deletedPageIDs.insert(page.id)
        currentPageIndex = min(currentPageIndex, pages.count - 1)
        structureDidChange()
    }

    func movePages(from source: IndexSet, to destination: Int) {
        let currentID = pages[currentPageIndex].id
        manifest.pages.move(fromOffsets: source, toOffset: destination)
        currentPageIndex = pages.firstIndex { $0.id == currentID } ?? 0
        structureDidChange()
    }

    func pageHasInk(at index: Int) -> Bool {
        pages.indices.contains(index) && !drawing(forPage: pages[index].id).strokes.isEmpty
    }

    func setBackground(_ background: PageBackground, forPageAt index: Int) {
        guard pages.indices.contains(index), pages[index].background != background else { return }
        manifest.pages[index].background = background
        refreshThumbnail(for: pages[index].id)
        structureDidChange()
    }

    func applyBackgroundToAllPages(_ background: PageBackground) {
        for index in pages.indices { manifest.pages[index].background = background }
        for page in pages { refreshThumbnail(for: page.id) }
        structureDidChange()
    }

    private func structureDidChange() {
        structureVersion += 1
        isManifestDirty = true
        scheduleSave()
    }

    // MARK: Saving

    private func scheduleSave() {
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
        guard !dirtyPageIDs.isEmpty || !deletedPageIDs.isEmpty || isManifestDirty else { return }
        do {
            for id in dirtyPageIDs {
                try store.saveDrawing(drawing(forPage: id), pageID: id, notebookID: manifest.id)
                refreshThumbnail(for: id)
            }
            dirtyPageIDs.removeAll()
            for id in deletedPageIDs {
                try store.deleteDrawing(pageID: id, notebookID: manifest.id)
            }
            deletedPageIDs.removeAll()
            manifest.updatedAt = .now
            try store.saveManifest(manifest)
            isManifestDirty = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshThumbnail(for id: UUID) {
        guard let page = pages.first(where: { $0.id == id }) else { return }
        thumbnails[id] = PageBackgroundRenderer.thumbnail(
            background: page.background, drawing: drawing(forPage: id), width: Self.thumbnailWidth
        )
    }
}
