import SwiftUI

@main
struct WritePadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: EditorViewModel?
    @State private var loadError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let editor {
                    NotebookEditorView(viewModel: editor)
                } else if let loadError {
                    ContentUnavailableView("Couldn't open notebook", systemImage: "exclamationmark.triangle",
                                           description: Text(loadError))
                } else {
                    ProgressView()
                }
            }
            .task {
                do {
                    editor = try EditorViewModel.openDefault()
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Never lose ink: flush pending autosave when leaving the foreground.
            if phase != .active { editor?.saveNow() }
        }
    }
}
