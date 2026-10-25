import SwiftData
import SwiftUI

struct NotebookWindowRequest: Codable, Hashable {
    var id = UUID()
    var notebookID: UUID?
}

@MainActor
final class LibraryResources {
    private var container: ModelContainer?
    private var store: NotebookStore?

    func makeLibrary() throws -> LibraryViewModel {
        if container == nil {
            let location = try StorageLocation.current()
            container = try location.makeContainer()
            store = NotebookStore(rootURL: location.notebooksURL)
        }
        guard let container, let store else { preconditionFailure("Library resources were not initialized") }
        return LibraryViewModel(container: container, store: store)
    }
}

struct LibrarySceneView: View {
    let resources: LibraryResources
    @Binding var request: NotebookWindowRequest?
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: LibraryViewModel?
    @State private var loadError: String?
    @State private var pendingPDFURL: URL?

    var body: some View {
        Group {
            if let library {
                LibraryView(viewModel: library)
                    .background(SceneLifetimeObserver(library: library).frame(width: 0, height: 0))
            } else if let loadError {
                ContentUnavailableView("Couldn't open library", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .preferredColorScheme(testAppearance)
        .task {
            guard library == nil else { return }
            do {
                let model = try resources.makeLibrary()
                try model.refresh()
                library = model
                if let id = request?.notebookID {
                    perform { try model.openNotebook(id: id) }
                }
                if let pendingPDFURL {
                    self.pendingPDFURL = nil
                    perform { try model.importPDF(from: pendingPDFURL) }
                }
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onOpenURL { url in
            guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
            if let library { perform { try library.importPDF(from: url) } } else { pendingPDFURL = url }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { library?.editor?.saveNow() }
            if phase == .active, library?.editor == nil { perform { try library?.refresh() } }
        }
        .onChange(of: NotebookAccessRegistry.shared.libraryVersion) {
            if library?.editor == nil { perform { try library?.refresh() } }
        }
        .onChange(of: library?.editor?.manifest.id) { _, id in
            if request == nil { request = NotebookWindowRequest() }
            request?.notebookID = id
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { library?.lastError = error.localizedDescription }
    }

    private var testAppearance: ColorScheme? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment[StorageLocation.namespaceKey] != nil else { return nil }
        switch environment["WRITEPAD_TEST_APPEARANCE"] {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

private struct SceneLifetimeObserver: UIViewRepresentable {
    let library: LibraryViewModel

    func makeCoordinator() -> Coordinator { Coordinator(library: library) }
    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.coordinator = context.coordinator
        return anchor
    }
    func updateUIView(_ view: Anchor, context: Context) {}
    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) { coordinator.library.disconnect() }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { coordinator?.scene = scene }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        let library: LibraryViewModel
        weak var scene: UIWindowScene?

        init(library: LibraryViewModel) {
            self.library = library
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(disconnected),
                                                   name: UIScene.didDisconnectNotification, object: nil)
        }

        @objc private func disconnected(_ notification: Notification) {
            guard let disconnected = notification.object as? UIWindowScene, disconnected === scene else { return }
            library.disconnect()
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
