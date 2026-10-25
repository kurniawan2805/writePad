import Observation
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
    var selectedFolderID: UUID?
    var searchText = ""
    var sortOrder = SortOrder.updated
    var lastError: String?

    // The context alone does not keep its container alive.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let store: NotebookStore

    init(container: ModelContainer, store: NotebookStore = NotebookStore()) {
        self.container = container
        self.store = store
        context.autosaveEnabled = false
    }

    var visibleNotebooks: [LibraryNotebook] {
        notebooks.filter {
            (selectedFolderID == nil || $0.folderID == selectedFolderID)
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
        folders.first { $0.id == selectedFolderID }?.title ?? "All Notebooks"
    }

    /// Packages remain authoritative for notebook titles and dates, including pre-library notebooks.
    func refresh() throws {
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
        try saveMetadata()
        let available = Set(manifests.map(\.id))
        notebooks = try context.fetch(FetchDescriptor<LibraryNotebook>()).filter { available.contains($0.id) }
        folders = try context.fetch(FetchDescriptor<LibraryFolder>()).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
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
            if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard hasScopedAccess || FileManager.default.isReadableFile(atPath: sourceURL.path()) else {
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
        context.insert(LibraryFolder(title: try validatedTitle(title)))
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
        try store.deleteNotebook(id: notebook.id)
        context.delete(notebook)
        try saveMetadata()
        try refresh()
    }

    func deleteFolder(_ folder: LibraryFolder) throws {
        let records = try context.fetch(FetchDescriptor<LibraryNotebook>())
        for notebook in records where notebook.folderID == folder.id { notebook.folderID = nil }
        if selectedFolderID == folder.id { selectedFolderID = nil }
        context.delete(folder)
        try saveMetadata()
        try refresh()
    }

    func openNotebook(_ notebook: LibraryNotebook) throws {
        let manifest = try store.loadManifest(id: notebook.id)
        editor = try EditorViewModel(store: store, manifest: manifest)
    }

    func closeNotebook() throws {
        editor?.saveNow()
        guard editor?.lastError == nil else { return }
        try refresh()
        editor = nil
    }

    func loadThumbnail(for notebook: LibraryNotebook) {
        guard thumbnails[notebook.id] == nil else { return }
        do {
            let manifest = try store.loadManifest(id: notebook.id)
            guard let page = manifest.pages.first else { return }
            let drawing = try store.loadDrawing(pageID: page.id, notebookID: notebook.id)
            thumbnails[notebook.id] = PageBackgroundRenderer.thumbnail(background: page.background, drawing: drawing, width: 180)
        } catch {
            lastError = error.localizedDescription
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
