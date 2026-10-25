import Observation
import PDFKit
import SwiftData
import UIKit

@MainActor
@Observable
final class LibraryViewModel {
    enum SortOrder: String, CaseIterable {
        case updated = "Last Edited", created = "Date Created", name = "Name"
    }

    private(set) var notebooks: [LibraryNotebook] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var thumbnails: [UUID: UIImage] = [:]
    private(set) var editor: EditorViewModel?
    private(set) var deletedNotebooks: [LibraryNotebook] = []
    var showingRecentlyDeleted = false
    var selectedFolderID: UUID?
    var searchText = ""
    var sortOrder = SortOrder.updated
    var lastError: String?

    // The context alone does not keep its container alive.
    private let container: ModelContainer
    private var context: ModelContext {
        container.mainContext
    }

    private(set) var thumbnailGeneration = 0
    private let store: NotebookStore

    init(container: ModelContainer, store: NotebookStore = NotebookStore()) {
        self.container = container
        self.store = store
        context.autosaveEnabled = false
    }

    var visibleNotebooks: [LibraryNotebook] {
        (showingRecentlyDeleted ? deletedNotebooks : notebooks).filter {
            (showingRecentlyDeleted || selectedFolderID == nil || $0.folderID == selectedFolderID)
                && (searchText.isEmpty || $0.title.localizedStandardContains(searchText))
        }.sorted { lhs, rhs in
            switch sortOrder {
            case .updated where lhs.updatedAt != rhs.updatedAt: return lhs.updatedAt > rhs.updatedAt
            case .created where lhs.createdAt != rhs.createdAt: return lhs.createdAt > rhs.createdAt
            default:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                return comparison == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
            }
        }
    }

    var title: String {
        showingRecentlyDeleted ? "Recently Deleted" : folders.first { $0.id == selectedFolderID }?.title ?? "All Notebooks"
    }

    /// Packages remain authoritative for notebook titles and dates, including pre-library notebooks.
    func refresh(now: Date = .now) throws {
        let manifests = try store.listNotebooks()
        let records = try context.fetch(FetchDescriptor<LibraryNotebook>())
        let indexed = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for manifest in manifests {
            if let record = indexed[manifest.id] {
                record.title = manifest.title
                record.createdAt = manifest.createdAt
                record.updatedAt = manifest.updatedAt
            } else {
                context.insert(LibraryNotebook(manifest: manifest))
            }
        }
        let trashed = try store.trashStore.listNotebooks()
        let trashIDs = Set(trashed.map(\.id))
        for manifest in trashed where indexed[manifest.id] == nil {
            context.insert(LibraryNotebook(manifest: manifest))
        }
        for record in try context.fetch(FetchDescriptor<LibraryNotebook>()) {
            if trashIDs.contains(record.id) {
                // If a move succeeded before metadata was saved, start a fresh retention period.
                if record.deletedAt == nil {
                    record.deletedAt = now
                }
                if let deletedAt = record.deletedAt, now.timeIntervalSince(deletedAt) >= 30 * 24 * 60 * 60 {
                    try store.trashStore.deleteNotebook(id: record.id)
                    context.delete(record)
                }
            } else if manifests.contains(where: { $0.id == record.id }) {
                record.deletedAt = nil
            }
        }
        try saveMetadata()
        deletedNotebooks = try context.fetch(FetchDescriptor<LibraryNotebook>()).filter {
            $0.deletedAt != nil && FileManager.default.fileExists(atPath: store.trashStore.packageURL(for: $0.id).path)
        }
        let available = Set(manifests.map(\.id))
        notebooks = try context.fetch(FetchDescriptor<LibraryNotebook>()).filter { available.contains($0.id) }
        folders = try context.fetch(FetchDescriptor<LibraryFolder>()).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        thumbnailGeneration += 1
        thumbnails.removeAll()
    }

    func createNotebook(title: String, background: PageBackground) throws {
        let manifest = try store.createNotebook(title: validatedTitle(title), background: background)
        context.insert(LibraryNotebook(manifest: manifest, folderID: selectedFolderID))
        try saveMetadata()
        try refresh()
    }

    func importPDF(from sourceURL: URL) throws {
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        guard hasScopedAccess || FileManager.default.isReadableFile(atPath: sourceURL.path(percentEncoded: false)) else {
            throw LibraryError.cannotReadPDF
        }

        let title = try validatedTitle(sourceURL.deletingPathExtension().lastPathComponent)
        let manifest = try store.importPDF(from: sourceURL, title: title)
        context.insert(LibraryNotebook(manifest: manifest, folderID: selectedFolderID))
        do {
            try saveMetadata()
        } catch {
            try? store.deleteNotebook(id: manifest.id)
            throw error
        }
        try refresh()
    }

    func createFolder(title: String) throws {
        try context.insert(LibraryFolder(title: validatedTitle(title)))
        try saveMetadata()
        try refresh()
    }

    func renameNotebook(_ notebook: LibraryNotebook, title: String) throws {
        var manifest = try store.loadManifest(id: notebook.id)
        manifest.title = try validatedTitle(title)
        manifest.updatedAt = .now
        try store.saveManifest(manifest)
        try refresh()
    }

    func renameFolder(_ folder: LibraryFolder, title: String) throws {
        folder.title = try validatedTitle(title)
        try saveMetadata()
        try refresh()
    }

    func moveNotebook(_ notebook: LibraryNotebook, to folderID: UUID?) throws {
        notebook.folderID = folderID
        try saveMetadata()
    }

    func deleteNotebook(_ notebook: LibraryNotebook) throws {
        try store.trashNotebook(id: notebook.id)
        notebook.deletedAt = .now
        try saveMetadata()
        try refresh()
    }

    func restoreNotebook(_ notebook: LibraryNotebook) throws {
        try store.restoreNotebook(id: notebook.id)
        notebook.deletedAt = nil
        try saveMetadata()
        try refresh()
    }

    func permanentlyDeleteNotebook(_ notebook: LibraryNotebook) throws {
        try store.trashStore.deleteNotebook(id: notebook.id)
        context.delete(notebook)
        try saveMetadata()
        try refresh()
    }

    func deleteFolder(_ folder: LibraryFolder) throws {
        let records = try context.fetch(FetchDescriptor<LibraryNotebook>())
        for notebook in records where notebook.folderID == folder.id {
            notebook.folderID = nil
        }
        if selectedFolderID == folder.id {
            selectedFolderID = nil
        }
        context.delete(folder)
        try saveMetadata()
        try refresh()
    }

    func openNotebook(_ notebook: LibraryNotebook) throws {
        let load = try store.loadManifestReport(id: notebook.id)
        editor = try EditorViewModel(store: store, manifest: load.manifest, notices: load.notices,
                                     needsSave: load.needsSave, readOnly: load.isReadOnly)
    }

    func closeNotebook() throws {
        editor?.saveNow()
        guard editor?.lastError == nil else { return }
        try refresh()
        editor = nil
    }

    func loadThumbnail(for notebook: LibraryNotebook) async {
        guard thumbnails[notebook.id] == nil else { return }
        let id = notebook.id
        let generation = thumbnailGeneration
        let store = notebook.deletedAt == nil ? self.store : self.store.trashStore
        do {
            let image = try await PageThumbnailJob.libraryImage(store: store, notebookID: id)
            guard !Task.isCancelled, thumbnailGeneration == generation else { return }
            thumbnails[id] = image
        } catch {
            if !Task.isCancelled, thumbnailGeneration == generation { lastError = error.localizedDescription }
        }
    }

    private func saveMetadata() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyTitle }
        return trimmed
    }

    private enum LibraryError: LocalizedError {
        case emptyTitle
        case cannotReadPDF

        var errorDescription: String? {
            switch self {
            case .emptyTitle: "Enter a name."
            case .cannotReadPDF: "writePad couldn't access that PDF. Try importing it again from Files."
            }
        }
    }
}
