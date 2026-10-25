import SwiftUI

struct ExportMenu: View {
    let viewModel: EditorViewModel
    @State private var isExporting = false
    @State private var isSharing = false
    @State private var fileURL: URL?
    @State private var exportError: String?

    var body: some View {
        Menu {
            Button("Export PDF", systemImage: "doc.richtext") { export(.pdf) }
            Button("Export Current Page as PNG", systemImage: "photo") {
                export(.png(pageID: viewModel.pages[viewModel.currentPageIndex].id))
            }
        } label: {
            if isExporting {
                ProgressView().accessibilityLabel("Preparing export")
            } else {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isExporting)
        .sheet(isPresented: $isSharing, onDismiss: removeExport) {
            if let fileURL { ExportShareSheet(url: fileURL) }
        }
        .alert("Couldn't export", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func export(_ format: NotebookExportFormat) {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                fileURL = try await viewModel.export(as: format)
                isSharing = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func removeExport() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        fileURL = nil
    }
}

private struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
