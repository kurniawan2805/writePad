import SwiftUI

struct NotebookEditorView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var canvasController = CanvasController()
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PageSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(260)
        } detail: {
            CanvasView(viewModel: viewModel, controller: canvasController)
                .background(Color(.secondarySystemBackground))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(viewModel.manifest.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
                .overlay(alignment: .bottom) { saveErrorBanner }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Undo", systemImage: "arrow.uturn.backward") { canvasController.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo", systemImage: "arrow.uturn.forward") { canvasController.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pages.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            paperMenu
            Button("Add Page", systemImage: "doc.badge.plus") {
                viewModel.addPage(after: viewModel.currentPageIndex)
            }
            Toggle(isOn: $viewModel.allowsFingerDrawing) {
                Label("Draw with Finger", systemImage: "hand.draw")
            }
            .toggleStyle(.button)
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
    private var saveErrorBanner: some View {
        if let error = viewModel.lastError {
            Text("Couldn't save: \(error)")
                .font(.footnote)
                .padding(8)
                .background(.red.opacity(0.9), in: .capsule)
                .foregroundStyle(.white)
                .padding()
        }
    }
}
