import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PageItemTools: View {
    @Bindable var viewModel: EditorViewModel
    @State private var importing = false
    @State private var draft: ItemDraft?
    @State private var photo: PhotosPickerItem?
    @State private var importPageID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Toggle("Edit Items", isOn: $viewModel.isEditingItems)
            Button("Text Box", systemImage: "textformat") {
                viewModel.isEditingItems = true
                let pageID = viewModel.pages[viewModel.currentPageIndex].id
                let item = PageItem(frame: CGRect(x: 48, y: 96, width: 260, height: 100), content: .text("", fontSize: 24))
                draft = ItemDraft(pageID: pageID, item: item.fitted(to: viewModel.pageSize(for: pageID)), isNew: true)
            }
            Button("Image from Files", systemImage: "photo") {
                importPageID = viewModel.pages[viewModel.currentPageIndex].id
                importing = true
            }
            PhotosPicker(selection: $photo, matching: .images) { Label("Photo Library", systemImage: "photo.on.rectangle") }
            if viewModel.selectedItem != nil {
                Button("Edit Selected Item", systemImage: "slider.horizontal.3") {
                    viewModel.isEditingItems = true
                    if let item = viewModel.selectedItem,
                       let pageID = viewModel.pages.first(where: {
                           viewModel.pageItems[$0.id]?.contains { $0.id == item.id } == true
                       })?.id {
                        draft = ItemDraft(pageID: pageID, item: item, isNew: false)
                    }
                }
                Button("Delete Selected Item", systemImage: "trash", role: .destructive) { viewModel.deleteSelectedItem() }
            }
        } label: {
            Label("Items", systemImage: viewModel.isEditingItems ? "rectangle.and.hand.point.up.left.filled" : "text.badge.plus")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let id = importPageID { try viewModel.addImage(Data(contentsOf: url), to: id) }
            } catch { errorMessage = error.localizedDescription }
        }
        .onChange(of: photo) { _, selected in
            let pageID = viewModel.pages[viewModel.currentPageIndex].id
            Task { @MainActor in
                do {
                    if let data = try await selected?.loadTransferable(type: Data.self) { try viewModel.addImage(data, to: pageID) }
                } catch { errorMessage = error.localizedDescription }
                photo = nil
            }
        }
        .sheet(item: $draft) { draft in
            PageItemEditor(item: draft.item, pageSize: viewModel.pageSize(for: draft.pageID)) { item in
                if draft.isNew {
                    viewModel.setItems((viewModel.pageItems[draft.pageID] ?? []) + [item], on: draft.pageID)
                } else {
                    viewModel.updateItem(item, on: draft.pageID)
                }
                viewModel.isEditingItems = true
                viewModel.selectedItemID = item.id
            }
        }
        .alert("Couldn't Import Image", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private struct ItemDraft: Identifiable {
        var id: UUID { item.id }
        let pageID: UUID
        let item: PageItem
        let isNew: Bool
    }
}

private struct PageItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: PageItem
    let pageSize: CGSize
    let save: (PageItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if case let .text(_, fontSize) = item.content {
                    TextEditor(text: textBinding)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Text Box Content")
                    Slider(value: fontBinding, in: 8...144) {
                        Text("Font Size")
                    }
                    Text("Font size: \(Int(fontSize))")
                }
                Section("Position and Size") {
                    dimension("Left", value: $item.frame.origin.x, limit: 0...pageSize.width)
                    dimension("Top", value: $item.frame.origin.y, limit: 0...pageSize.height)
                    dimension("Width", value: $item.frame.size.width, limit: 32...max(32, pageSize.width))
                    dimension("Height", value: $item.frame.size.height, limit: 32...max(32, pageSize.height))
                }
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(item); dismiss() } }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: {
            if case let .text(text, _) = item.content { return text }
            return ""
        }, set: { text in
            if case let .text(_, size) = item.content { item.content = .text(text, fontSize: size) }
        })
    }

    private var fontBinding: Binding<Double> {
        Binding(get: {
            if case let .text(_, size) = item.content { return size }
            return 24
        }, set: { size in
            if case let .text(text, _) = item.content { item.content = .text(text, fontSize: size) }
        })
    }

    private func dimension(_ name: String, value: Binding<CGFloat>, limit: ClosedRange<CGFloat>) -> some View {
        Stepper("\(name): \(Int(value.wrappedValue))", value: value, in: limit, step: 8)
    }
}
