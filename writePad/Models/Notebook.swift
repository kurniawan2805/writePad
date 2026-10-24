import Foundation

/// Contents of `manifest.json` inside a `.writepad` package.
struct NotebookManifest: Codable, Equatable, Identifiable, Sendable {
    static let currentVersion = 1

    var id: UUID
    var title: String
    var version: Int
    var pages: [PageInfo]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, pages: [PageInfo] = [PageInfo()], date: Date = .now) {
        self.id = id
        self.title = title
        self.version = Self.currentVersion
        self.pages = pages
        self.createdAt = date
        self.updatedAt = date
    }
}

struct PageInfo: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var background: PageBackground

    init(id: UUID = UUID(), background: PageBackground = .blank) {
        self.id = id
        self.background = background
    }
}

enum PageBackground: String, Codable, CaseIterable, Sendable {
    case blank, lined, grid, dotted
}
