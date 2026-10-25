import PDFKit
import SwiftUI

struct PDFTools: View {
    let viewModel: EditorViewModel
    @Bindable var pdf: PDFNotebook
    let showNavigation: () -> Void
    @State private var showsComment = false
    @State private var needsSelection = false
    @State private var commentPageID: UUID?
    @State private var commentPoint: CGPoint?

    var body: some View {
        Toggle(isOn: $pdf.isDrawing) {
            Label("Draw on PDF", systemImage: "pencil.tip")
        }
        .toggleStyle(.button)
        Menu {
            Button("Pages, Outline, Search & Comments", systemImage: "sidebar.left", action: showNavigation)
            Divider()
            Button("Highlight Selection", systemImage: "highlighter") { annotate(.highlight) }
            Button("Underline Selection", systemImage: "underline") { annotate(.underline) }
            Button("Strikethrough Selection", systemImage: "strikethrough") { annotate(.strikeOut) }
            Button("Add Comment", systemImage: "note.text.badge.plus") {
                let index = viewModel.currentPageIndex
                commentPageID = viewModel.pages[index].id
                if let page = pdf.document.page(at: index), let selection = pdf.view?.currentSelection,
                   selection.pages.contains(page) {
                    commentPoint = selection.bounds(for: page).origin
                } else {
                    commentPoint = nil
                }
                showsComment = true
            }
        } label: {
            Label("PDF Tools", systemImage: "doc.text.magnifyingglass")
        }
        .sheet(isPresented: $showsComment) {
            PDFCommentEditor(text: "") { text in
                if let commentPageID { pdf.addComment(text, pageID: commentPageID, at: commentPoint) }
            }
        }
        .alert("Select PDF text first", isPresented: $needsSelection) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn off Draw on PDF, then touch and hold text to select it. You can also select a search result.")
        }
    }

    private func annotate(_ kind: PDFMarkup.Kind) {
        guard let selection = pdf.view?.currentSelection, pdf.annotate(selection, kind: kind) > 0 else {
            needsSelection = true
            return
        }
        pdf.view?.clearSelection()
    }
}

struct PDFCommentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    let save: (String) -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .accessibilityLabel("Comment")
                .padding()
                .navigationTitle("Comment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save Comment") {
                            save(text)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
