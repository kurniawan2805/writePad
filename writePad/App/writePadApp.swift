import SwiftUI

@main
struct WritePadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: LibraryViewModel?
    @State private var loadError: String?
    @State private var pendingPDFURL: URL?

    var body: some Scene {
        WindowGroup {
            Group {
                if let library {
                    LibraryView(viewModel: library)
                } else if let loadError {
                    ContentUnavailableView("Couldn't open library", systemImage: "exclamationmark.triangle",
                                           description: Text(loadError))
                } else {
                    ProgressView()
                }
            }
            .preferredColorScheme(testAppearance)
            .task {
                do {
                    guard library == nil else { return }
                    let location = try StorageLocation.current()
                    let model = LibraryViewModel(
                        container: try location.makeContainer(),
                        store: NotebookStore(rootURL: location.notebooksURL)
                    )
                    try model.refresh()
                    library = model
                    if let pendingPDFURL {
                        self.pendingPDFURL = nil
                        importPDF(pendingPDFURL, into: model)
                    }
                } catch {
                    loadError = error.localizedDescription
                }
            }
            .onOpenURL { url in
                guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
                if let library {
                    importPDF(url, into: library)
                } else {
                    pendingPDFURL = url
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Never lose ink: flush pending autosave when leaving the foreground.
            if phase != .active { library?.editor?.saveNow() }
        }
    }

    private var testAppearance: ColorScheme? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["WRITEPAD_STORAGE_NAMESPACE"] != nil else { return nil }
        switch environment["WRITEPAD_TEST_APPEARANCE"] {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private func importPDF(_ url: URL, into library: LibraryViewModel) {
        do {
            try library.importPDF(from: url)
        } catch {
            library.lastError = error.localizedDescription
        }
    }
}
