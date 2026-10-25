import SwiftUI

struct NotebookCard: View {
    let notebook: LibraryNotebook
    let thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable()
                } else {
                    Rectangle().fill(.white).overlay { ProgressView() }
                }
            }
            .aspectRatio(PageLayout.pageSize, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 4))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            Text(notebook.title)
                .font(.headline)
                .lineLimit(2)
            Text(notebook.updatedAt, format: .dateTime.month().day().year())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
