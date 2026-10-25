import Foundation
import Observation
import PDFKit
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
    /// What had to be repaired to open this notebook (damaged files set aside, a backup restored). Not a save error.
    private(set) var recoveryNotice: String?
    /// Bumped whenever pages are added, removed, reordered or restyled, so the canvas rebuilds.
    private(set) var structureVersion = 0
    private(set) var scrollRequest: ScrollRequest?
    private(set) var currentPageIndex = 0
    var allowsFingerDrawing: Bool
    let pdf: PDFNotebook?
    /// True when a newer build saved this notebook: it is shown, but nothing in it changes and nothing is written.
    let isReadOnly: Bool

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

    /// Serial, so writes never overlap or reorder. Autosaves run on it in the background; `saveNow` waits its turn.
    @ObservationIgnored private let writeQueue = DispatchQueue(label: "writePad.notebook-save", qos: .utility)
    @ObservationIgnored private var isWriting = false
    /// What the running background write carries, so a flush can include it.
    @ObservationIgnored private var inFlight = PendingChanges()
    @ObservationIgnored private var saveSequence = 0
    /// The last save started by `saveNow`; background writes before it were rewritten by it.
    @ObservationIgnored private var flushedThrough = 0
    @ObservationIgnored private var thumbnailVersions: [UUID: Int] = [:]
    @ObservationIgnored private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]

    private struct PendingChanges {
        var pages: Set<UUID> = []
        var deleted: Set<UUID> = []
        var markups = false
    }

    private let store: NotebookStore

    static let thumbnailWidth: CGFloat = 140

    var pages: [PageInfo] { manifest.pages }
    private var layout: PageLayout { PageLayout(pageCount: pages.count) }

    init(store: NotebookStore, manifest: NotebookManifest, notices: [String] = [], needsSave: Bool = false,
         readOnly: Bool = false) throws {
        self.store = store
        self.manifest = manifest
        self.isReadOnly = readOnly || manifest.isNewerThanSupported
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
        if pdf?.pruneOrphanedMarkups() == true, !isReadOnly { isPDFDirty = true }
        pdf?.onChange = { [weak self] id in
            self?.isPDFDirty = true
            self?.refreshThumbnails([id])
            self?.scheduleSave()
        }
        refreshThumbnails(manifest.pages.map(\.id))
        if needsSave, !isReadOnly {
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
        return try EditorViewModel(store: store, manifest: load.manifest, notices: load.notices,
                                   needsSave: load.needsSave, readOnly: load.isReadOnly)
    }

    func dismissRecoveryNotice() { recoveryNotice = nil }

    // MARK: Ink

    func drawing(forPage id: UUID) -> PKDrawing { pageDrawings[id] ?? PKDrawing() }

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
        guard !isReadOnly else { return }
        for (page, newDrawing) in zip(pages, layout.split(combined)) where newDrawing != pageDrawings[page.id] {
            pageDrawings[page.id] = newDrawing
            dirtyPageIDs.insert(page.id)
        }
        scheduleSave()
    }

    func drawingDidChange(_ drawing: PKDrawing, pageID: UUID) {
        guard !isReadOnly, pages.contains(where: { $0.id == pageID }), drawing != pageDrawings[pageID] else { return }
        pageDrawings[pageID] = drawing
        dirtyPageIDs.insert(pageID)
        scheduleSave()
    }

    // MARK: Pages

    func pageDidBecomeVisible(_ index: Int) { if currentPageIndex != index { currentPageIndex = index } }

    func scrollToPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        currentPageIndex = index
        scrollRequest = ScrollRequest(pageIndex: index)
    }

    /// Inserts a page after `index` (or at the end) using the same paper as its neighbor.
    func addPage(after index: Int? = nil) {
        guard !isReadOnly else { return }
        let insertIndex = min((index ?? pages.count - 1) + 1, pages.count)
        let background = pages[max(insertIndex - 1, 0)].background
        let page = PageInfo(background: background)
        manifest.pages.insert(page, at: insertIndex)
        pageDrawings[page.id] = PKDrawing()
        structureDidChange()
        refreshThumbnails([page.id])
        scrollToPage(insertIndex)
    }

    func deletePage(at index: Int) {
        guard !isReadOnly, pages.count > 1, pages.indices.contains(index) else { return }
        let page = manifest.pages.remove(at: index)
        pageDrawings[page.id] = nil
        thumbnails[page.id] = nil
        dirtyPageIDs.remove(page.id)
        deletedPageIDs.insert(page.id)
        currentPageIndex = min(currentPageIndex, pages.count - 1)
        structureDidChange()
    }

    func movePages(from source: IndexSet, to destination: Int) {
        guard !isReadOnly else { return }
        let currentID = pages[currentPageIndex].id
        manifest.pages.move(fromOffsets: source, toOffset: destination)
        currentPageIndex = pages.firstIndex { $0.id == currentID } ?? 0
        structureDidChange()
    }

    func toggleBookmark(at index: Int) {
        guard !isReadOnly, pages.indices.contains(index) else { return }
        manifest.pages[index].isBookmarked.toggle()
        structureDidChange()
    }

    func pageIndices(bookmarkedOnly: Bool) -> [Int] {
        pages.indices.filter { !bookmarkedOnly || pages[$0].isBookmarked }
    }

    func pageHasInk(at index: Int) -> Bool {
        pages.indices.contains(index) && !drawing(forPage: pages[index].id).strokes.isEmpty
    }

    func setBackground(_ background: PageBackground, forPageAt index: Int) {
        guard !isReadOnly, pages.indices.contains(index), pages[index].background != background else { return }
        manifest.pages[index].background = background
        structureDidChange()
        refreshThumbnails([pages[index].id])
    }

    func applyBackgroundToAllPages(_ background: PageBackground) {
        guard !isReadOnly else { return }
        for index in pages.indices { manifest.pages[index].background = background }
        structureDidChange()
        refreshThumbnails(pages.map(\.id))
    }

    private func structureDidChange() {
        pdf?.rebuild(pages: pages)
        if pdf?.pruneOrphanedMarkups() == true { isPDFDirty = true }
        structureVersion += 1
        isManifestDirty = true
        scheduleSave()
    }
}

// MARK: - Saving

extension EditorViewModel {
    private var hasUnsavedChanges: Bool {
        !dirtyPageIDs.isEmpty || !deletedPageIDs.isEmpty || isManifestDirty || isPDFDirty
    }

    private func scheduleSave() {
        guard !isReadOnly else { return }
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
            self?.autosave()
        }
    }

    /// The timer's save: changes are captured here and written on `writeQueue`, off the main actor.
    private func autosave() {
        pendingSave = nil
        guard !isReadOnly, hasUnsavedChanges else { return }
        // One background write at a time; when it finishes it schedules the next if anything changed meanwhile.
        guard !isWriting else { return }
        let (snapshot, changes) = takeSnapshot(includingInFlight: false)
        saveSequence += 1
        let sequence = saveSequence
        isWriting = true
        inFlight = changes
        let store = store
        writeQueue.async {
            let result = Result { try store.write(snapshot) }
            Task { @MainActor [weak self] in
                self?.finishBackgroundWrite(sequence, changes: changes, result: result)
            }
        }
    }

    private func finishBackgroundWrite(_ sequence: Int, changes: PendingChanges,
                                       result: Result<NotebookManifest, any Error>) {
        isWriting = false
        inFlight = PendingChanges()
        switch result {
        case let .success(written):
            saveSucceeded(written, pages: changes.pages)
        case let .failure(error):
            // A `saveNow` that started after this write already wrote everything it carried.
            if sequence > flushedThrough { saveFailed(error, changes: changes) }
        }
        if hasUnsavedChanges, pendingSave == nil { scheduleSave() }
    }

    /// Writes everything now and returns when it is on disk (or has failed), after any background write still
    /// running. Used when the app leaves the foreground, when a notebook closes, and by tests.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard !isReadOnly, hasUnsavedChanges || isWriting else {
            unsavedSince = nil
            return
        }
        let (snapshot, changes) = takeSnapshot(includingInFlight: true)
        saveSequence += 1
        flushedThrough = saveSequence
        let store = store
        let result = writeQueue.sync { Result { try store.write(snapshot) } }
        switch result {
        case let .success(written): saveSucceeded(written, pages: changes.pages)
        case let .failure(error): saveFailed(error, changes: changes)
        }
    }

    /// Captures what to write and marks it clean. Changes made while it is written count as new changes.
    private func takeSnapshot(includingInFlight: Bool) -> (NotebookStore.SaveSnapshot, PendingChanges) {
        var changes = PendingChanges(pages: dirtyPageIDs, deleted: deletedPageIDs, markups: isPDFDirty)
        if includingInFlight {
            changes.pages.formUnion(inFlight.pages)
            changes.deleted.formUnion(inFlight.deleted)
            changes.markups = changes.markups || inFlight.markups
        }
        changes.pages = changes.pages.filter { pageDrawings[$0] != nil } // deleted since they changed
        dirtyPageIDs.removeAll()
        deletedPageIDs.removeAll()
        isPDFDirty = false
        isManifestDirty = false
        unsavedSince = nil
        let snapshot = NotebookStore.SaveSnapshot(
            manifest: manifest,
            drawings: Dictionary(uniqueKeysWithValues: changes.pages.map { ($0, drawing(forPage: $0)) }),
            markups: changes.markups ? pdf?.markups : nil,
            deletedPageIDs: changes.deleted
        )
        return (snapshot, changes)
    }

    private func saveSucceeded(_ written: NotebookManifest, pages: Set<UUID>) {
        manifest.updatedAt = written.updatedAt
        manifest.version = written.version
        lastError = nil
        saveFailures = 0
        retryNotBefore = nil
        refreshThumbnails(pages)
    }

    /// Everything the failed save carried becomes unsaved again, and a retry is scheduled with backoff so a full
    /// disk isn't hammered.
    private func saveFailed(_ error: any Error, changes: PendingChanges) {
        dirtyPageIDs.formUnion(changes.pages.filter { pageDrawings[$0] != nil })
        deletedPageIDs.formUnion(changes.deleted)
        isPDFDirty = isPDFDirty || changes.markups
        isManifestDirty = true
        lastError = error.localizedDescription
        saveFailures += 1
        let retryAt = ContinuousClock.now + saveTiming.retryDelay(afterFailures: saveFailures)
        retryNotBefore = retryAt
        unsavedSince = unsavedSince ?? .now
        schedule(at: retryAt)
    }

    // MARK: Thumbnails

    private func refreshThumbnails(_ ids: some Collection<UUID>) {
        let jobs = ids.compactMap { id -> PageThumbnailJob? in
            guard let page = pages.first(where: { $0.id == id }) else { return nil }
            thumbnailVersions[id, default: 0] += 1
            return PageThumbnailJob(id: id, version: thumbnailVersions[id] ?? 0, background: page.background,
                                pdfPageIndex: page.pdfPageIndex, drawing: drawing(forPage: id),
                                markups: pdf?.markups.filter { $0.pageID == id } ?? [])
        }
        guard !jobs.isEmpty else { return }
        let sourceURL = store.sourcePDFURL(for: manifest.id)
        let width = Self.thumbnailWidth
        let token = UUID()
        thumbnailTasks[token] = Task { [weak self] in
            for await (job, image) in PageThumbnailJob.images(for: jobs, sourceURL: sourceURL, width: width) {
                self?.setThumbnail(image, for: job)
            }
            self?.thumbnailTaskFinished(token)
        }
    }

    private func setThumbnail(_ image: UIImage, for job: PageThumbnailJob) {
        // A newer render of the same page may already be on its way; and the page may have been deleted.
        guard thumbnailVersions[job.id] == job.version, pages.contains(where: { $0.id == job.id }) else { return }
        thumbnails[job.id] = image
    }

    private func thumbnailTaskFinished(_ token: UUID) {
        thumbnailTasks[token] = nil
    }

    /// Waits until every requested thumbnail has been rendered. For tests.
    func waitForThumbnails() async {
        while let (token, task) = thumbnailTasks.first {
            await task.value
            thumbnailTasks[token] = nil
        }
    }
}
