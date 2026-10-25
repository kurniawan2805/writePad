import Foundation
import SwiftData

@Model
final class LibraryNotebook {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var folderID: UUID?
    var deletedAt: Date?

    init(manifest: NotebookManifest, folderID: UUID? = nil) {
        id = manifest.id
        title = manifest.title
        createdAt = manifest.createdAt
        updatedAt = manifest.updatedAt
        self.folderID = folderID
    }
}

@Model
final class LibraryFolder {
    @Attribute(.unique) var id: UUID
    var title: String

    init(title: String) {
        id = UUID()
        self.title = title
    }
}
