import Foundation
import PencilKit
import PDFKit

/// Reads and writes `.writepad` packages:
///
///     <id>.writepad/
///       manifest.json
///       pages/<pageId>.drawing
struct NotebookStore: Sendable {
    enum StoreError: LocalizedError, Equatable {
        case unsupportedVersion(Int)
        case invalidPDF

        var errorDescription: String? {
            switch self {
            case let .unsupportedVersion(version): "This notebook uses an unsupported format version (\(version))."
            case .invalidPDF: "This file isn't a readable PDF."
            }
        }
    }

    static let packageExtension = "writepad"
    static let sourcePDFFilename = "source.pdf"

    let rootURL: URL

    init(rootURL: URL = URL.documentsDirectory) {
        self.rootURL = rootURL
    }

    // MARK: Paths

    func packageURL(for notebookID: UUID) -> URL {
        rootURL.appending(path: "\(notebookID.uuidString).\(Self.packageExtension)", directoryHint: .isDirectory)
    }

    func sourcePDFURL(for notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: Self.sourcePDFFilename)
    }

    private func manifestURL(for notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: "manifest.json")
    }

    private func drawingURL(pageID: UUID, notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: "pages/\(pageID.uuidString).drawing")
    }

    // MARK: Notebooks

    @discardableResult
    func createNotebook(title: String, background: PageBackground = .blank) throws -> NotebookManifest {
        let manifest = NotebookManifest(title: title, pages: [PageInfo(background: background)])
        try FileManager.default.createDirectory(
            at: packageURL(for: manifest.id).appending(path: "pages"),
            withIntermediateDirectories: true
        )
        try saveManifest(manifest)
        return manifest
    }

    @discardableResult
    func importPDF(from sourceURL: URL, title: String) throws -> NotebookManifest {
        guard let document = PDFDocument(url: sourceURL), !document.isLocked, document.pageCount > 0 else {
            throw StoreError.invalidPDF
        }

        let pages = (0..<document.pageCount).map { PageInfo(pdfPageIndex: $0) }
        let manifest = NotebookManifest(title: title, pages: pages)
        let packageURL = packageURL(for: manifest.id)

        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: false)
        do {
            try FileManager.default.createDirectory(
                at: packageURL.appending(path: "pages"),
                withIntermediateDirectories: false
            )
            try FileManager.default.copyItem(at: sourceURL, to: sourcePDFURL(for: manifest.id))
            try saveManifest(manifest)
            return manifest
        } catch {
            try? FileManager.default.removeItem(at: packageURL)
            throw error
        }
    }

    func listNotebooks() throws -> [NotebookManifest] {
        guard FileManager.default.fileExists(atPath: rootURL.path(percentEncoded: false)) else { return [] }
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

    func deleteNotebook(id: UUID) throws {
        try FileManager.default.removeItem(at: packageURL(for: id))
    }

    // MARK: Drawings

    func loadPDFMarkups(notebookID: UUID) throws -> [PDFMarkup] {
        let url = packageURL(for: notebookID).appending(path: "annotations.json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try Self.decoder.decode([PDFMarkup].self, from: Data(contentsOf: url))
    }

    func savePDFMarkups(_ markups: [PDFMarkup], notebookID: UUID) throws {
        try Self.encoder.encode(markups).write(
            to: packageURL(for: notebookID).appending(path: "annotations.json"), options: .atomic
        )
    }

    /// Returns an empty drawing when the page has never been saved.
    func loadDrawing(pageID: UUID, notebookID: UUID) throws -> PKDrawing {
        let url = drawingURL(pageID: pageID, notebookID: notebookID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return PKDrawing() }
        return try PKDrawing(data: Data(contentsOf: url))
    }

    func saveDrawing(_ drawing: PKDrawing, pageID: UUID, notebookID: UUID) throws {
        let url = drawingURL(pageID: pageID, notebookID: notebookID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try drawing.dataRepresentation().write(to: url, options: .atomic)
    }

    func deleteDrawing(pageID: UUID, notebookID: UUID) throws {
        let url = drawingURL(pageID: pageID, notebookID: notebookID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
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
