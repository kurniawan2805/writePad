import SwiftUI

struct PageSidebarView: View {
    let viewModel: EditorViewModel
    @State private var pendingDeleteIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        viewModel.scrollToPage(index)
                    } label: {
                        PageThumbnail(
                            image: viewModel.thumbnails[page.id],
                            number: index + 1,
                            isCurrent: index == viewModel.currentPageIndex
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .id(page.id)
                    .contextMenu { menu(forPageAt: index) }
                }
                .onMove(perform: viewModel.movePages)
                .onDelete { offsets in
                    if let index = offsets.first { requestDelete(at: index) }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.currentPageIndex) { _, index in
                guard viewModel.pages.indices.contains(index) else { return }
                withAnimation { proxy.scrollTo(viewModel.pages[index].id) }
            }
        }
        .toolbar {
            // Top bar only: the bottom edge is covered by the floating tool picker.
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button("Add Page", systemImage: "plus") {
                    viewModel.addPage(after: viewModel.currentPageIndex)
                }
            }
        }
        .confirmationDialog(
            "Delete this page?",
            isPresented: Binding(get: { pendingDeleteIndex != nil }, set: { if !$0 { pendingDeleteIndex = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Page", role: .destructive) {
                if let index = pendingDeleteIndex { viewModel.deletePage(at: index) }
            }
        } message: {
            Text("The writing and annotations on this page will be permanently deleted.")
        }
    }

    @ViewBuilder
    private func menu(forPageAt index: Int) -> some View {
        Button("Add Page After", systemImage: "plus") { viewModel.addPage(after: index) }
        Button("Move Up", systemImage: "arrow.up") {
            viewModel.movePages(from: [index], to: index - 1)
        }
        .disabled(index == 0)
        Button("Move Down", systemImage: "arrow.down") {
            viewModel.movePages(from: [index], to: index + 2)
        }
        .disabled(index == viewModel.pages.count - 1)
        if viewModel.pages[index].pdfPageIndex == nil {
            Menu("Paper", systemImage: "doc.text") {
                ForEach(PageBackground.allCases, id: \.self) { background in
                    Button(background.title, systemImage: background.systemImage) {
                        viewModel.setBackground(background, forPageAt: index)
                    }
                }
            }
        }
        Divider()
        Button("Delete Page", systemImage: "trash", role: .destructive) { requestDelete(at: index) }
            .disabled(viewModel.pages.count == 1)
    }

    private func requestDelete(at index: Int) {
        guard viewModel.pages.count > 1 else { return }
        if viewModel.pageHasInk(at: index) || viewModel.pdf?.page(for: viewModel.pages[index].id)?.annotations.isEmpty == false {
            pendingDeleteIndex = index
        } else {
            viewModel.deletePage(at: index)
        }
    }
}

private struct PageThumbnail: View {
    let image: UIImage?
    let number: Int
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image).resizable()
                } else {
                    Color.white
                }
            }
            .aspectRatio(PageLayout.pageSize, contentMode: .fit)
            .frame(width: EditorViewModel.thumbnailWidth)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 3)
            }
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(number)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
