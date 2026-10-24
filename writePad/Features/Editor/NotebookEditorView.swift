import SwiftUI

struct NotebookEditorView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var canvasController = CanvasController()

    var body: some View {
        CanvasView(
            initialDrawing: viewModel.drawing,
            allowsFingerDrawing: viewModel.allowsFingerDrawing,
            controller: canvasController,
            onDrawingChange: viewModel.drawingDidChange
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(viewModel.manifest.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Undo", systemImage: "arrow.uturn.backward") { canvasController.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo", systemImage: "arrow.uturn.forward") { canvasController.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $viewModel.allowsFingerDrawing) {
                    Label("Draw with Finger", systemImage: "hand.draw")
                }
                .toggleStyle(.button)
            }
        }
        .overlay(alignment: .bottom) {
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
}
