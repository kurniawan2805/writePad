import Foundation

/// Contents of `manifest.json` inside a `.writepad` package.
///
/// Keys this build doesn't know (written by a newer build) are kept in `unknownFields` and written back unchanged.
struct NotebookManifest: Codable, Equatable, Identifiable, Sendable {
    static let currentVersion = 3

    var id: UUID
    var title: String
    var version: Int
    var pages: [PageInfo]
    var createdAt: Date
    var updatedAt: Date
    var unknownFields: [String: JSONValue] = [:]

    /// True when a newer build wrote this manifest; such notebooks open read-only.
    var isNewerThanSupported: Bool { version > Self.currentVersion }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, version, pages, createdAt, updatedAt
    }

    init(id: UUID = UUID(), title: String, pages: [PageInfo] = [PageInfo()], date: Date = .now) {
        self.id = id
        self.title = title
        self.version = Self.currentVersion
        self.pages = pages
        self.createdAt = date
        self.updatedAt = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        version = try container.decode(Int.self, forKey: .version)
        pages = try container.decode([PageInfo].self, forKey: .pages)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        unknownFields = try UnknownFields.decode(from: decoder, known: CodingKeys.allCases.map(\.rawValue))
    }

    func encode(to encoder: Encoder) throws {
        try UnknownFields.encode(unknownFields, to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(version, forKey: .version)
        try container.encode(pages, forKey: .pages)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct PageInfo: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var background: PageBackground
    var pdfPageIndex: Int?
    var unknownFields: [String: JSONValue] = [:]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, background, pdfPageIndex
    }

    init(id: UUID = UUID(), background: PageBackground = .blank, pdfPageIndex: Int? = nil) {
        self.id = id
        self.background = background
        self.pdfPageIndex = pdfPageIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        background = try container.decode(PageBackground.self, forKey: .background)
        pdfPageIndex = try container.decodeIfPresent(Int.self, forKey: .pdfPageIndex)
        unknownFields = try UnknownFields.decode(from: decoder, known: CodingKeys.allCases.map(\.rawValue))
    }

    func encode(to encoder: Encoder) throws {
        try UnknownFields.encode(unknownFields, to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(background, forKey: .background)
        try container.encodeIfPresent(pdfPageIndex, forKey: .pdfPageIndex)
    }
}

enum PageBackground: String, Codable, CaseIterable, Sendable {
    case blank, lined, grid, dotted
}
