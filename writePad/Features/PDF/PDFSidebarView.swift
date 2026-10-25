import PDFKit
import SwiftUI

struct PDFSidebarView: View {
    enum Tab: String, CaseIterable {
        case pages = "Pages", outline = "Outline", search = "Search", comments = "Comments"
    }

    let viewModel: EditorViewModel
    let pdf: PDFNotebook
    @State private var tab = Tab.pages
    @State private var query = ""
    @State private var editingComment: PDFMarkup?

    var body: some View {
        VStack(spacing: 0) {
            Picker("PDF Navigation", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("PDF Navigation")
            .padding(.horizontal)
            Group {
                switch tab {
                case .pages: PageSidebarView(viewModel: viewModel)
                case .outline: outline
                case .search: search
                case .comments: comments
                }
            }
        }
        .navigationTitle(tab.rawValue)
        .sheet(item: $editingComment) { comment in
            PDFCommentEditor(text: comment.text) { text in pdf.updateComment(id: comment.id, text: text) }
        }
    }

    private var outline: some View {
        List {
            if pdf.outline.isEmpty {
                Text("This PDF has no outline.").foregroundStyle(.secondary)
            }
            ForEach(pdf.outline.filter { item in pdf.pages.contains { $0.id == item.pageID } }) { item in
                Button(item.title) { jump(to: item.pageID) }
                    .padding(.leading, CGFloat(item.depth) * 12)
            }
        }
    }

    private var search: some View {
        VStack {
            TextField("Search PDF Text", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit { pdf.search(query) }
                .onChange(of: query) { _, query in pdf.search(query) }
            List {
                if !query.isEmpty && pdf.searchResults.isEmpty {
                    Text("No text matches. Scanned PDFs may not contain searchable text.").foregroundStyle(.secondary)
                }
                ForEach(Array(pdf.searchResults.enumerated()), id: \.offset) { index, selection in
                    Button {
                        pdf.isDrawing = false
                        pdf.view?.setCurrentSelection(selection, animate: true)
                        pdf.view?.go(to: selection)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(selection.string ?? "Result \(index + 1)").lineLimit(2)
                            if let page = selection.pages.first, let id = pdf.pageID(for: page),
                               let pageIndex = pdf.pages.firstIndex(where: { $0.id == id }) {
                                Text("Page \(pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("PDF Search Result \(index + 1)")
                }
            }
        }
    }

    private var comments: some View {
        List {
            let visible = (pdf.sourceComments + pdf.markups).filter { markup in pdf.pages.contains { $0.id == markup.pageID } }
            if visible.isEmpty { Text("No annotations yet.").foregroundStyle(.secondary) }
            ForEach(visible) { markup in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        jump(to: markup.pageID)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(markup.text.isEmpty ? markup.kind.rawValue : markup.text)
                            Text("\(markup.kind.rawValue.capitalized) · Page \((pdf.pages.firstIndex { $0.id == markup.pageID } ?? 0) + 1)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if markup.kind == .comment, pdf.markups.contains(where: { $0.id == markup.id }) {
                        Button("Edit Comment") { editingComment = markup }.font(.caption)
                    }
                }
                .swipeActions {
                    if pdf.markups.contains(where: { $0.id == markup.id }) {
                        Button("Delete", role: .destructive) { pdf.removeMarkup(id: markup.id) }
                    }
                }
                .contextMenu {
                    if pdf.markups.contains(where: { $0.id == markup.id }) {
                        Button("Delete Annotation", role: .destructive) { pdf.removeMarkup(id: markup.id) }
                    }
                }
            }
        }
    }

    private func jump(to id: UUID) {
        if let index = pdf.pages.firstIndex(where: { $0.id == id }) { viewModel.scrollToPage(index) }
    }
}
