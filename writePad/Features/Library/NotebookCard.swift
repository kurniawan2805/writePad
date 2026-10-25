import SwiftUI

struct NotebookCard: View {
    let notebook: LibraryNotebook
    let thumbnail: UIImage?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable()
                } else {
                    Rectangle().fill(.white).overlay { ProgressView() }
                }
            }
            // PDF pages keep their own shape (Letter, landscape, cropped) instead of A4.
            .aspectRatio(thumbnail?.size ?? PageLayout.pageSize, contentMode: .fit)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 140 : .infinity)
            .clipShape(.rect(cornerRadius: 4))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .accessibilityHidden(true)
            Text(notebook.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(notebook.updatedAt, format: .dateTime.month().day().year())
                .font(.caption)
                .foregroundStyle(Color.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
