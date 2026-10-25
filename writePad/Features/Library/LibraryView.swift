import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var form: LibraryItemForm.Request?
    @State private var notebookToDelete: LibraryNotebook?
    @State private var folderToDelete: LibraryFolder?
    @State private var isImportingPDF = false

    var body: some View {
        NavigationSplitView {
            List {
                Button {
                    viewModel.showingRecentlyDeleted = false
                    viewModel.selectedFolderID = nil
                } label: {
                    LibrarySidebarLabel(title: "All Notebooks", systemImage: "books.vertical")
                }
                .listRowBackground(rowBackground(selected: viewModel.selectedFolderID == nil && !viewModel.showingRecentlyDeleted))
                .accessibilityAddTraits(viewModel.selectedFolderID == nil && !viewModel.showingRecentlyDeleted ? .isSelected : [])
                Button {
                    viewModel.showingRecentlyDeleted = true
                } label: {
                    LibrarySidebarLabel(title: "Recently Deleted", systemImage: "trash")
                }
                .listRowBackground(rowBackground(selected: viewModel.showingRecentlyDeleted))
                .accessibilityAddTraits(viewModel.showingRecentlyDeleted ? .isSelected : [])
                Section {
                    Text("Folders")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .accessibilityAddTraits(.isHeader)
                        .listRowBackground(Color(.secondarySystemBackground))
                    ForEach(viewModel.folders) { folder in
                        Button {
                            viewModel.showingRecentlyDeleted = false
                            viewModel.selectedFolderID = folder.id
                        } label: {
                            LibrarySidebarLabel(title: folder.title, systemImage: "folder")
                        }
                        .listRowBackground(rowBackground(
                            selected: viewModel.selectedFolderID == folder.id && !viewModel.showingRecentlyDeleted
                        ))
                        .accessibilityAddTraits(
                            viewModel.selectedFolderID == folder.id && !viewModel.showingRecentlyDeleted ? .isSelected : []
                        )
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { showForm(.renameFolder(folder)) }
                            Button("Delete Folder", systemImage: "trash", role: .destructive) { folderToDelete = folder }
                        }
                    }
                    Button { showForm(.newFolder) } label: {
                        LibrarySidebarLabel(title: "New Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color(.secondarySystemBackground))
                }
            }
            .navigationTitle("writePad")
        } detail: {
            NavigationStack {
                notebookGrid
                    .navigationTitle(viewModel.title)
                    .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "Search by title")
                    .toolbar { libraryToolbar }
            }
        }
        .sheet(item: $form) { LibraryItemForm(request: $0, library: viewModel) }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                perform { try viewModel.importPDF(from: url) }
            case let .failure(error):
                viewModel.lastError = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.editor != nil },
            set: {
                if !$0 {
                    perform { try viewModel.closeNotebook() }
                }
            }
        )) {
            if let editor = viewModel.editor {
                NotebookEditorView(viewModel: editor) { perform { try viewModel.closeNotebook() } }
                    .interactiveDismissDisabled()
            }
        }
        .alert("Couldn't update library", isPresented: Binding(
            get: { viewModel.lastError != nil }, set: {
                if !$0 {
                    viewModel.lastError = nil
                }
            }
        )) {
            Button("OK") { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
        .confirmationDialog("Delete notebook?", isPresented: Binding(
            get: { notebookToDelete != nil }, set: {
                if !$0 {
                    notebookToDelete = nil
                }
            }
        ), titleVisibility: .visible) {
            Button(viewModel.showingRecentlyDeleted ? "Delete Now" : "Delete Notebook", role: .destructive) {
                if let notebook = notebookToDelete {
                    perform {
                        if viewModel.showingRecentlyDeleted {
                            try viewModel.permanentlyDeleteNotebook(notebook)
                        } else {
                            try viewModel.deleteNotebook(notebook)
                        }
                    }
                }
                notebookToDelete = nil
            }
        } message: {
            Text(viewModel.showingRecentlyDeleted
                ? "The notebook and all its writing will be permanently deleted."
                : "You can restore this notebook from Recently Deleted for 30 days.")
        }
        .confirmationDialog("Delete folder?", isPresented: Binding(
            get: { folderToDelete != nil }, set: {
                if !$0 {
                    folderToDelete = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderToDelete {
                    perform { try viewModel.deleteFolder(folder) }
                }
                folderToDelete = nil
            }
        } message: {
            Text("Its notebooks will remain in All Notebooks.")
        }
    }

    private func rowBackground(selected: Bool) -> Color {
        Color(selected ? UIColor.tertiarySystemBackground : UIColor.secondarySystemBackground)
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 180, maximum: 240), alignment: .top)]
    }

    private var notebookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(viewModel.visibleNotebooks) { notebook in
                    Button {
                        if !viewModel.showingRecentlyDeleted {
                            perform { try viewModel.openNotebook(notebook) }
                        }
                    } label: {
                        NotebookCard(notebook: notebook, thumbnail: viewModel.thumbnails[notebook.id])
                    }
                    .buttonStyle(.plain)
                    .contextMenu { notebookMenu(notebook) }
                    .task(id: viewModel.thumbnailGeneration) { await viewModel.loadThumbnail(for: notebook) }
                }
            }
            .padding(24)
        }
        .background(Color(.secondarySystemBackground))
        .overlay {
            if viewModel.visibleNotebooks.isEmpty {
                if viewModel.showingRecentlyDeleted && viewModel.searchText.isEmpty {
                    ContentUnavailableView("No Deleted Notebooks", systemImage: "trash",
                                           description: Text("Deleted notebooks stay here for 30 days."))
                } else if viewModel.searchText.isEmpty {
                    ContentUnavailableView {
                        Label(viewModel.selectedFolderID == nil ? "No Notebooks" : "This Folder Is Empty",
                              systemImage: viewModel.selectedFolderID == nil ? "books.vertical" : "folder")
                    } description: {
                        Text(viewModel.selectedFolderID == nil
                            ? "Create a notebook or import a PDF to start writing."
                            : "Create a notebook here, import a PDF, or move a notebook into this folder.")
                    } actions: {
                        Button("New Notebook") { showForm(.newNotebook) }.buttonStyle(.borderedProminent)
                        Button("Import PDF", systemImage: "square.and.arrow.down") { isImportingPDF = true }
                    }
                } else {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if supportsMultipleWindows {
                Button("New Window", systemImage: "macwindow.badge.plus") {
                    openWindow(value: NotebookWindowRequest())
                }
            }
            Button("Import PDF", systemImage: "square.and.arrow.down") { isImportingPDF = true }
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort by", selection: $viewModel.sortOrder) {
                    ForEach(LibraryViewModel.SortOrder.allCases, id: \.self) { order in Text(order.rawValue).tag(order) }
                }
            }
            Menu("Create", systemImage: "plus") {
                Button("New Notebook", systemImage: "doc.badge.plus") { showForm(.newNotebook) }
                Button("New Folder", systemImage: "folder.badge.plus") { showForm(.newFolder) }
            }
        }
    }

    @ViewBuilder
    private func notebookMenu(_ notebook: LibraryNotebook) -> some View {
        if viewModel.showingRecentlyDeleted {
            Button("Restore", systemImage: "arrow.uturn.backward") { perform { try viewModel.restoreNotebook(notebook) } }
            Button("Delete Now", systemImage: "trash", role: .destructive) { notebookToDelete = notebook }
        } else {
            if supportsMultipleWindows {
                Button("Open in New Window", systemImage: "rectangle.on.rectangle") {
                    openWindow(value: NotebookWindowRequest(notebookID: notebook.id))
                }
            }
            Button("Rename", systemImage: "pencil") { showForm(.renameNotebook(notebook)) }
            Menu("Move to Folder", systemImage: "folder") {
                Button("No Folder") { perform { try viewModel.moveNotebook(notebook, to: nil) } }
                ForEach(viewModel.folders) { folder in
                    Button(folder.title) { perform { try viewModel.moveNotebook(notebook, to: folder.id) } }
                }
            }
            Button("Delete Notebook", systemImage: "trash", role: .destructive) { notebookToDelete = notebook }
        }
    }

    private func showForm(_ action: LibraryItemForm.Action) {
        form = LibraryItemForm.Request(action: action)
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { viewModel.lastError = error.localizedDescription }
    }
}

private struct LibrarySidebarLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
