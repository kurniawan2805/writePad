import SwiftUI

struct LibraryItemForm: View {
    enum Action {
        case newNotebook, newFolder, renameNotebook(LibraryNotebook), renameFolder(LibraryFolder)
    }

    struct Request: Identifiable {
        let id = UUID()
        let action: Action

        var title: String {
            switch action {
            case .newNotebook: "New Notebook"
            case .newFolder: "New Folder"
            case .renameNotebook, .renameFolder: "Rename"
            }
        }

        var initialName: String {
            switch action {
            case .newNotebook, .newFolder: ""
            case let .renameNotebook(notebook): notebook.title
            case let .renameFolder(folder): folder.title
            }
        }
    }

    let request: Request
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var name: String
    @State private var paper = PageBackground.blank
    @State private var error: String?

    init(request: Request, library: LibraryViewModel) {
        self.request = request
        self.library = library
        _name = State(initialValue: request.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .onSubmit(save)
                if case .newNotebook = request.action {
                    Picker("Paper", selection: $paper) {
                        ForEach(PageBackground.allCases, id: \.self) { background in
                            Label(background.title, systemImage: background.systemImage)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(request.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
    }

    private func save() {
        do {
            switch request.action {
            case .newNotebook: try library.createNotebook(title: name, background: paper)
            case .newFolder: try library.createFolder(title: name)
            case let .renameNotebook(notebook): try library.renameNotebook(notebook, title: name)
            case let .renameFolder(folder): try library.renameFolder(folder, title: name)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
