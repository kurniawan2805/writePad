import PencilKit
import UIKit

extension EditorViewModel {
    struct ScrollRequest: Equatable {
        let id = UUID()
        let pageIndex: Int
    }

    func combinedDrawing() -> PKDrawing {
        PageLayout(pageCount: pages.count).merge(pages.map { drawing(forPage: $0.id) })
    }

    func export(as format: NotebookExportFormat, directory: URL = .temporaryDirectory) async throws -> URL {
        let snapshot = NotebookExport(
            manifest: manifest,
            drawings: Dictionary(uniqueKeysWithValues: pages.map { ($0.id, drawing(forPage: $0.id).dataRepresentation()) }),
            sourcePDFURL: store.sourcePDFURL(for: manifest.id),
            markups: pdf?.markups ?? [],
            pageItems: pageItems, imageAssets: imageAssets
        )
        return try await Task.detached(priority: .userInitiated) {
            try NotebookExporter.export(snapshot, as: format, directory: directory)
        }.value
    }

    func pageIndices(bookmarkedOnly: Bool) -> [Int] {
        pages.indices.filter { !bookmarkedOnly || pages[$0].isBookmarked }
    }

    func pageHasContent(at index: Int) -> Bool {
        guard pages.indices.contains(index) else { return false }
        let id = pages[index].id
        return !drawing(forPage: id).strokes.isEmpty || !(pageItems[id] ?? []).isEmpty
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

    var selectedItem: PageItem? {
        pageItems.values.lazy.flatMap { $0 }.first { $0.id == selectedItemID }
    }

    func pageSize(for id: UUID) -> CGSize {
        if let index = pages.firstIndex(where: { $0.id == id }), let page = pdf?.document.page(at: index) {
            return PDFPageCanvas.displaySize(for: page)
        }
        return PageLayout.pageSize
    }

    func addText(_ text: String = "Text", to pageID: UUID) {
        guard !isReadOnly, pages.contains(where: { $0.id == pageID }) else { return }
        let item = PageItem(frame: CGRect(x: 48, y: 96, width: 260, height: 100), content: .text(text, fontSize: 24))
        setItems((pageItems[pageID] ?? []) + [item.fitted(to: pageSize(for: pageID))], on: pageID)
        if !isReadOnly { isEditingItems = true; selectedItemID = item.id }
    }

    func addImage(_ data: Data, to pageID: UUID) throws {
        guard !isReadOnly, pages.contains(where: { $0.id == pageID }) else { return }
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Bound imported photos and normalize orientation before persisting a PNG.
        let scale = min(1, 2048 / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        let assetID = UUID()
        retainImage(normalized, id: assetID)
        let pageSize = pageSize(for: pageID)
        let width = min(280, pageSize.width - 64)
        let height = min(width * size.height / size.width, pageSize.height - 128)
        let item = PageItem(frame: CGRect(x: 32, y: 96, width: width, height: height), content: .image(assetID))
        setItems((pageItems[pageID] ?? []) + [item], on: pageID)
        isEditingItems = true
        selectedItemID = item.id
    }

    func updateItem(_ item: PageItem, on pageID: UUID) {
        guard var items = pageItems[pageID], let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item.fitted(to: pageSize(for: pageID))
        setItems(items, on: pageID)
    }

    func deleteSelectedItem() {
        guard let id = selectedItemID,
              let pageID = pages.first(where: { pageItems[$0.id]?.contains { $0.id == id } == true })?.id else { return }
        setItems((pageItems[pageID] ?? []).filter { $0.id != id }, on: pageID)
        selectedItemID = nil
    }

    func setItems(_ items: [PageItem], on pageID: UUID) {
        guard !isReadOnly, pages.contains(where: { $0.id == pageID }) else { return }
        let items = items.map { $0.fitted(to: pageSize(for: pageID)) }
        let previous = pageItems[pageID] ?? []
        guard previous != items else { return }
        let grouping = !itemUndoManager.isUndoing && !itemUndoManager.isRedoing
        if grouping { itemUndoManager.beginUndoGrouping() }
        itemUndoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.setItems(previous, on: pageID) }
        }
        itemUndoManager.setActionName("Page Items")
        if grouping { itemUndoManager.endUndoGrouping() }
        commitItems(items, on: pageID)
    }
}
