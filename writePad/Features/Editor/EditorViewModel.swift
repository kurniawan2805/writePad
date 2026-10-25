import Foundation
import Observation
import PDFKit
import PencilKit
import UIKit

/// When autosave runs and how it backs off. Pure, so the timing rules can be tested without waiting.
struct SaveTiming: Sendable, Equatable {
    /// Quiet time after the last change before writing.
    var delay: Duration = .seconds(1)
    /// However often changes push the save back, it starts within this long of the first unsaved change.
    var maxLatency: Duration = .seconds(5)
    /// Wait before the first retry of a failed save; doubles with each failure.
    var retryBase: Duration = .seconds(1)
    var retryCap: Duration = .seconds(60)

    /// `notBefore` is the end of a retry backoff: changes made while a save keeps failing don't retry sooner.
    func deadline(now: ContinuousClock.Instant, firstUnsaved: ContinuousClock.Instant,
                  notBefore: ContinuousClock.Instant? = nil) -> ContinuousClock.Instant {
        let due = min(now + delay, firstUnsaved + maxLatency)
        return notBefore.map { max(due, $0) } ?? due
    }

    func retryDelay(afterFailures failures: Int) -> Duration {
        min(retryBase * (1 << min(max(failures - 1, 0), 6)), retryCap)
    }
}

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
    /// What had to be repaired to open this notebook (damaged files set aside, a backup restored). Not a save error.
    private(set) var recoveryNotice: String?
    /// Bumped whenever pages are added, removed, reordered or restyled, so the canvas rebuilds.
    private(set) var structureVersion = 0
    private(set) var scrollRequest: ScrollRequest?
    private(set) var currentPageIndex = 0
    var allowsFingerDrawing: Bool
    let pdf: PDFNotebook?

    /// Page-local drawings, keyed by page ID. Not observed: it changes on every stroke.
    @ObservationIgnored private var pageDrawings: [UUID: PKDrawing]
    @ObservationIgnored private var dirtyPageIDs: Set<UUID> = []
    @ObservationIgnored private var deletedPageIDs: Set<UUID> = []
    @ObservationIgnored private var isManifestDirty = false
    @ObservationIgnored private var isPDFDirty = false
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// When the oldest change not yet on disk was made; nil when everything is saved.
    @ObservationIgnored private var unsavedSince: ContinuousClock.Instant?
    @ObservationIgnored private var saveFailures = 0
    @ObservationIgnored private var retryNotBefore: ContinuousClock.Instant?
    @ObservationIgnored var saveTiming = SaveTiming()

    private let store: NotebookStore

    static let thumbnailWidth: CGFloat = 140

    var pages: [PageInfo] { manifest.pages }
    private var layout: PageLayout { PageLayout(pageCount: pages.count) }

    init(store: NotebookStore, manifest: NotebookManifest, notices: [String] = [], needsSave: Bool = false) throws {
        self.store = store
        self.manifest = manifest
        let sourceURL = store.sourcePDFURL(for: manifest.id)
        let hasSourcePDF = FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false))
        if manifest.pages.contains(where: { $0.pdfPageIndex != nil }), !hasSourcePDF {
            throw NotebookStore.StoreError.invalidPDF
        }
        self.pdf = hasSourcePDF
            ? try PDFNotebook(url: sourceURL, pages: manifest.pages, markups: store.loadPDFMarkups(notebookID: manifest.id)) : nil
        var notices = notices
        var drawings: [UUID: PKDrawing] = [:]
        for page in manifest.pages {
            let load = try store.loadDrawingReport(pageID: page.id, notebookID: manifest.id)
            drawings[page.id] = load.drawing
            notices += load.notices
        }
        self.pageDrawings = drawings
        self.recoveryNotice = notices.isEmpty ? nil : notices.joined(separator: " ")
        #if targetEnvironment(simulator)
        self.allowsFingerDrawing = true // the simulator has no Apple Pencil
        #else
        self.allowsFingerDrawing = false
        #endif
        // Older packages may still hold annotations of pages deleted before pruning existed.
        if pdf?.pruneOrphanedMarkups() == true { isPDFDirty = true }
        pdf?.onChange = { [weak self] id in
            self?.isPDFDirty = true
            self?.refreshThumbnail(for: id)
            self?.scheduleSave()
        }
        for page in manifest.pages { refreshThumbnail(for: page.id) }
        if needsSave {
            isManifestDirty = true
            scheduleSave()
        }
    }

    /// Opens the most recently edited notebook, or creates the first one.
    static func openDefault(store: NotebookStore = NotebookStore()) throws -> EditorViewModel {
        guard let latest = try store.listNotebooks().first else {
            return try EditorViewModel(store: store, manifest: store.createNotebook(title: "My Notebook"))
        }
        let load = try store.loadManifestReport(id: latest.id)
        return try EditorViewModel(store: store, manifest: load.manifest, notices: load.notices, needsSave: load.needsSave)
    }

    func dismissRecoveryNotice() {
        recoveryNotice = nil
    }

    // MARK: Ink

    func drawing(forPage id: UUID) -> PKDrawing {
        pageDrawings[id] ?? PKDrawing()
    }

    func combinedDrawing() -> PKDrawing {
        layout.merge(pages.map { drawing(forPage: $0.id) })
    }

    func export(as format: NotebookExportFormat, directory: URL = .temporaryDirectory) async throws -> URL {
        let snapshot = NotebookExport(
            manifest: manifest,
            drawings: pageDrawings.mapValues { $0.dataRepresentation() },
            sourcePDFURL: store.sourcePDFURL(for: manifest.id),
            markups: pdf?.markups ?? []
        )
        return try await Task.detached(priority: .userInitiated) {
            try NotebookExporter.export(snapshot, as: format, directory: directory)
        }.value
    }

    func drawingDidChange(_ combined: PKDrawing) {
        for (page, newDrawing) in zip(pages, layout.split(combined)) where newDrawing != pageDrawings[page.id] {
            pageDrawings[page.id] = newDrawing
            dirtyPageIDs.insert(page.id)
        }
        scheduleSave()
    }

    func drawingDidChange(_ drawing: PKDrawing, pageID: UUID) {
        guard pages.contains(where: { $0.id == pageID }), drawing != pageDrawings[pageID] else { return }
        pageDrawings[pageID] = drawing
        dirtyPageIDs.insert(pageID)
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
        structureDidChange()
        refreshThumbnail(for: pages[index].id)
    }

    func applyBackgroundToAllPages(_ background: PageBackground) {
        for index in pages.indices { manifest.pages[index].background = background }
        structureDidChange()
        for page in pages { refreshThumbnail(for: page.id) }
    }

    private func structureDidChange() {
        pdf?.rebuild(pages: pages)
        if pdf?.pruneOrphanedMarkups() == true { isPDFDirty = true }
        structureVersion += 1
        isManifestDirty = true
        scheduleSave()
    }

    // MARK: Saving

    private func scheduleSave() {
        let now = ContinuousClock.now
        let since = unsavedSince ?? now
        unsavedSince = since
        schedule(at: saveTiming.deadline(now: now, firstUnsaved: since, notBefore: retryNotBefore))
    }

    private func schedule(at deadline: ContinuousClock.Instant) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard !dirtyPageIDs.isEmpty || !deletedPageIDs.isEmpty || isManifestDirty || isPDFDirty else {
            unsavedSince = nil
            return
        }
        // Keep a failed manifest write retryable even after drawing files have been saved.
        isManifestDirty = true
        do {
            for id in dirtyPageIDs {
                try store.saveDrawing(drawing(forPage: id), pageID: id, notebookID: manifest.id)
                refreshThumbnail(for: id)
            }
            dirtyPageIDs.removeAll()
            if isPDFDirty, let pdf {
                try store.savePDFMarkups(pdf.markups, notebookID: manifest.id)
                isPDFDirty = false
            }
            manifest.version = NotebookManifest.currentVersion
            manifest.updatedAt = .now
            try store.saveManifest(manifest)
            isManifestDirty = false
            for id in deletedPageIDs {
                try store.deleteDrawing(pageID: id, notebookID: manifest.id)
            }
            deletedPageIDs.removeAll()
            lastError = nil
            unsavedSince = nil
            saveFailures = 0
            retryNotBefore = nil
        } catch {
            lastError = error.localizedDescription
            // Everything stays dirty; try again on our own, backing off so a full disk isn't hammered.
            saveFailures += 1
            let retryAt = ContinuousClock.now + saveTiming.retryDelay(afterFailures: saveFailures)
            retryNotBefore = retryAt
            unsavedSince = unsavedSince ?? .now
            schedule(at: retryAt)
        }
    }

    private func refreshThumbnail(for id: UUID) {
        guard let page = pages.first(where: { $0.id == id }) else { return }
        if let pdfPage = pdf?.page(for: id) {
            thumbnails[id] = PageBackgroundRenderer.thumbnail(
                pdfPage: pdfPage, drawing: drawing(forPage: id), width: Self.thumbnailWidth
            )
            return
        }
        thumbnails[id] = PageBackgroundRenderer.thumbnail(
            background: page.background, drawing: drawing(forPage: id), width: Self.thumbnailWidth
        )
    }
}
