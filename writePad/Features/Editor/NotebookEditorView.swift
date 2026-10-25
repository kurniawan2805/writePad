import SwiftUI

struct NotebookEditorView: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onClose: (() -> Void)?
    @State private var canvasController = CanvasController()
    @AppStorage(ShapeSnapper.enabledKey) private var shapeSnapEnabled = true
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if let pdf = viewModel.pdf {
                    PDFSidebarView(viewModel: viewModel, pdf: pdf)
                } else {
                    PageSidebarView(viewModel: viewModel)
                }
            }
            .navigationSplitViewColumnWidth(300)
        } detail: {
            Group {
                if let pdf = viewModel.pdf {
                    PDFCanvasView(viewModel: viewModel, pdf: pdf, controller: canvasController)
                } else {
                    CanvasView(viewModel: viewModel, controller: canvasController)
                }
            }
                .background(Color(.secondarySystemBackground))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(viewModel.manifest.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !viewModel.isReadOnly, viewModel.pdf?.isDrawing != false {
                        PenTrayView(state: viewModel.penTray).disabled(viewModel.isEditingItems)
                    }
                }
                .overlay(alignment: .bottom) { saveErrorBanner }
                .overlay(alignment: .top) { recoveryBanner }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if let onClose {
                Button("Library", systemImage: "books.vertical", action: onClose)
            }
            if !viewModel.isReadOnly {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    if viewModel.isEditingItems { viewModel.itemUndoManager.undo() } else { canvasController.undo() }
                }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo", systemImage: "arrow.uturn.forward") {
                    if viewModel.isEditingItems { viewModel.itemUndoManager.redo() } else { canvasController.redo() }
                }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let pdf = viewModel.pdf {
                PDFTools(viewModel: viewModel, pdf: pdf) {
                    columnVisibility = .all
                }
            }
            Button {
                viewModel.toggleBookmark(at: viewModel.currentPageIndex)
            } label: {
                let bookmarked = viewModel.pages[viewModel.currentPageIndex].isBookmarked
                Label(bookmarked ? "Remove Bookmark" : "Bookmark Page", systemImage: bookmarked ? "star.fill" : "star")
            }
            .disabled(viewModel.isReadOnly)
            ExportMenu(viewModel: viewModel)
            pagePosition
            if viewModel.isReadOnly {
                Label("Read-Only", systemImage: "lock")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                PageItemTools(viewModel: viewModel)
                if viewModel.pages[viewModel.currentPageIndex].pdfPageIndex == nil { paperMenu }
                Button("Add Page", systemImage: "doc.badge.plus") {
                    viewModel.addPage(after: viewModel.currentPageIndex)
                }
                Toggle(isOn: $viewModel.allowsFingerDrawing) {
                    Label("Draw with Finger", systemImage: "hand.draw")
                }
                .toggleStyle(.button)
                Toggle(isOn: $shapeSnapEnabled) {
                    Label("Shape Snap", systemImage: "square.on.circle")
                }
                .toggleStyle(.button)
                .help("Hold the pen still at the end of a stroke to straighten it into a line or shape")
            }
        }
    }

    private var pagePosition: some View {
        let current = viewModel.currentPageIndex + 1
        let total = viewModel.pages.count
        return Button {
            columnVisibility = .all
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "doc.on.doc")
            } else {
                Text("\(current) / \(total)")
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
            }
        }
        .accessibilityLabel("Pages")
        .accessibilityValue("Page \(current) of \(total)")
    }

    private var paperMenu: some View {
        let index = viewModel.currentPageIndex
        let current = viewModel.pages.indices.contains(index) ? viewModel.pages[index].background : .blank
        return Menu {
            Picker("Paper for This Page", selection: Binding(
                get: { current },
                set: { viewModel.setBackground($0, forPageAt: index) }
            )) {
                ForEach(PageBackground.allCases, id: \.self) { background in
                    Label(background.title, systemImage: background.systemImage)
                }
            }
            Button("Apply to All Pages", systemImage: "square.stack") {
                viewModel.applyBackgroundToAllPages(current)
            }
        } label: {
            Label("Paper", systemImage: current.systemImage)
        }
    }

    @ViewBuilder
    private var recoveryBanner: some View {
        if let notice = viewModel.recoveryNotice {
            HStack {
                Label(notice, systemImage: "exclamationmark.triangle")
                Button("OK") { viewModel.dismissRecoveryNotice() }
                    .buttonStyle(.bordered)
            }
                .font(.footnote)
                .padding(8)
                .background(.orange.opacity(0.9), in: .capsule)
                .foregroundStyle(.white)
                .padding()
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let error = viewModel.lastError {
            HStack {
                Text("Couldn't save: \(error)")
                Button("Retry") { viewModel.saveNow() }
                    .buttonStyle(.bordered)
            }
                .font(.footnote)
                .padding(8)
                .background(.red.opacity(0.9), in: .capsule)
                .foregroundStyle(.white)
                .padding()
        }
    }
}
