import Foundation
import PencilKit

/// Reads and writes `.writepad` packages:
///
///     <id>.writepad/
///       manifest.json
///       pages/<pageId>.drawing
struct NotebookStore: Sendable {
    enum StoreError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    static let packageExtension = "writepad"

    let rootURL: URL

    init(rootURL: URL = URL.documentsDirectory) {
        self.rootURL = rootURL
    }

    // MARK: Paths

    func packageURL(for notebookID: UUID) -> URL {
        rootURL.appending(path: "\(notebookID.uuidString).\(Self.packageExtension)", directoryHint: .isDirectory)
    }

    private func manifestURL(for notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: "manifest.json")
    }

    private func drawingURL(pageID: UUID, notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: "pages/\(pageID.uuidString).drawing")
    }

    // MARK: Notebooks

    @discardableResult
    func createNotebook(title: String) throws -> NotebookManifest {
        let manifest = NotebookManifest(title: title)
        try FileManager.default.createDirectory(
            at: packageURL(for: manifest.id).appending(path: "pages"),
            withIntermediateDirectories: true
        )
        try saveManifest(manifest)
        return manifest
    }

    func listNotebooks() throws -> [NotebookManifest] {
        guard FileManager.default.fileExists(atPath: rootURL.path()) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        return urls
            .filter { $0.pathExtension == Self.packageExtension }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .compactMap { try? loadManifest(id: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadManifest(id: UUID) throws -> NotebookManifest {
        let data = try Data(contentsOf: manifestURL(for: id))
        let manifest = try Self.decoder.decode(NotebookManifest.self, from: data)
        guard manifest.version <= NotebookManifest.currentVersion else {
            throw StoreError.unsupportedVersion(manifest.version)
        }
        return manifest
    }

    func saveManifest(_ manifest: NotebookManifest) throws {
        let data = try Self.encoder.encode(manifest)
        try data.write(to: manifestURL(for: manifest.id), options: .atomic)
    }

    // MARK: Drawings

    /// Returns an empty drawing when the page has never been saved.
    func loadDrawing(pageID: UUID, notebookID: UUID) throws -> PKDrawing {
        let url = drawingURL(pageID: pageID, notebookID: notebookID)
        guard FileManager.default.fileExists(atPath: url.path()) else { return PKDrawing() }
        return try PKDrawing(data: Data(contentsOf: url))
    }

    func saveDrawing(_ drawing: PKDrawing, pageID: UUID, notebookID: UUID) throws {
        let url = drawingURL(pageID: pageID, notebookID: notebookID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try drawing.dataRepresentation().write(to: url, options: .atomic)
    }

    // MARK: Coding

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateFormat))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try dateFormat.parse(decoder.singleValueContainer().decode(String.self))
        }
        return decoder
    }()

    /// ISO 8601 with milliseconds, so notebooks created in the same second still sort correctly.
    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
