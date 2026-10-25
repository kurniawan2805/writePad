import SwiftUI

struct NotebookEditorView: View {
    @Bindable var viewModel: EditorViewModel
    var onClose: (() -> Void)?
    @State private var canvasController = CanvasController()
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
                Button("Undo", systemImage: "arrow.uturn.backward") { canvasController.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo", systemImage: "arrow.uturn.forward") { canvasController.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let pdf = viewModel.pdf {
                PDFTools(viewModel: viewModel, pdf: pdf) {
                    columnVisibility = .all
                }
            }
            ExportMenu(viewModel: viewModel)
            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pages.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if viewModel.isReadOnly {
                Label("Read-Only", systemImage: "lock")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if viewModel.pages[viewModel.currentPageIndex].pdfPageIndex == nil { paperMenu }
                Button("Add Page", systemImage: "doc.badge.plus") {
                    viewModel.addPage(after: viewModel.currentPageIndex)
                }
                Toggle(isOn: $viewModel.allowsFingerDrawing) {
                    Label("Draw with Finger", systemImage: "hand.draw")
                }
                .toggleStyle(.button)
            }
        }
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
