import Foundation
import PencilKit
import PDFKit

/// Reads and writes `.writepad` packages:
///
///     <id>.writepad/
///       manifest.json
///       manifest.prev.json        the manifest as it was before the last save, read if manifest.json is damaged
///       pages/<pageId>.drawing
///
/// A file that can't be decoded is renamed to `<name>.corrupt` and never overwritten, so a bug or a bad write
/// can't turn damaged-but-recoverable data into lost data.
struct NotebookStore: Sendable {
    enum StoreError: LocalizedError, Equatable {
        case unsupportedVersion(Int)
        case invalidPDF
        case corruptManifest(setAside: [String])

        var errorDescription: String? {
            switch self {
            case let .unsupportedVersion(version): "This notebook uses an unsupported format version (\(version))."
            case .invalidPDF: "This file isn't a readable PDF."
            case .corruptManifest: "This notebook's manifest is damaged and has no usable backup. The damaged file was kept."
            }
        }
    }

    /// A manifest plus what had to be done to read it (empty when nothing).
    struct ManifestLoad: Sendable {
        var manifest: NotebookManifest
        var notices: [String] = []
        /// True when the manifest was changed in memory (pages recovered) and should be saved.
        var needsSave = false
    }

    /// A drawing plus what had to be done to read it (empty when nothing).
    struct DrawingLoad: Sendable {
        var drawing: PKDrawing
        var notices: [String] = []
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

    private func previousManifestURL(for notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: "manifest.prev.json")
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

    /// Cheap read for listings: no page recovery, which scans the notebook's pages folder.
    func loadManifest(id: UUID) throws -> NotebookManifest {
        try loadManifestReport(id: id, recoveringPages: false).manifest
    }

    /// Reads `manifest.json`, falling back to `manifest.prev.json` when it is missing or damaged. A damaged file is set
    /// aside, and a manifest from a newer version is never set aside or replaced by an older backup. With
    /// `recoveringPages`, drawings written just before a crash that the manifest never listed are added as pages.
    func loadManifestReport(id: UUID, recoveringPages: Bool = true) throws -> ManifestLoad {
        let primary = manifestURL(for: id), backup = previousManifestURL(for: id)
        var setAside: [String] = []
        var notices: [String] = []
        for url in [primary, backup] {
            guard let data = try readIfPresent(url) else { continue }
            let manifest: NotebookManifest
            do {
                manifest = try Self.decoder.decode(NotebookManifest.self, from: data)
            } catch {
                if let moved = try? quarantine(url) { setAside.append(moved.lastPathComponent) }
                continue
            }
            guard manifest.version <= NotebookManifest.currentVersion else {
                throw StoreError.unsupportedVersion(manifest.version)
            }
            if url == backup {
                // Put the backup in place so the next load, and the next save's backup, start from a valid file.
                try? data.write(to: primary, options: .atomic)
                notices.append("The notebook's manifest was damaged; the version from before the last save was restored.")
            }
            if !setAside.isEmpty {
                notices.append("Damaged file kept as \(setAside.joined(separator: ", ")).")
            }
            var load = ManifestLoad(manifest: manifest, notices: notices, needsSave: false)
            if recoveringPages {
                let recovered = recoverOrphanedPages(into: &load.manifest)
                if recovered > 0 {
                    load.notices.append("Recovered \(recovered) page(s) written just before the app last quit.")
                    load.needsSave = true
                }
            }
            return load
        }
        guard setAside.isEmpty else { throw StoreError.corruptManifest(setAside: setAside) }
        _ = try Data(contentsOf: primary) // nothing there: throws the file error callers already expect
        throw CocoaError(.fileReadNoSuchFile)
    }

    /// The file's contents, or nil if it doesn't exist. A present but unreadable file (as opposed to an undecodable
    /// one) may be a passing I/O or data-protection error, so it throws: falling back to an older backup would let
    /// the next save overwrite the newer manifest.
    private func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { throw error }
            return nil
        }
    }

    /// A save writes drawings first and the manifest last, so a crash in between leaves drawings the manifest doesn't
    /// list. Those are told apart from pages deleted on purpose by age: a deleted page's drawing is older than the
    /// manifest that dropped it, a crashed save's is newer than the manifest it never reached. Returns how many were added.
    private func recoverOrphanedPages(into manifest: inout NotebookManifest) -> Int {
        let directory = packageURL(for: manifest.id).appending(path: "pages")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let known = Set(manifest.pages.map(\.id))
        let orphans = files.compactMap { file -> (id: UUID, written: Date)? in
            guard file.pathExtension == "drawing",
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !known.contains(id),
                  let written = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  written > manifest.updatedAt,
                  let data = try? Data(contentsOf: file), (try? Self.decodeDrawing(data)) != nil else { return nil }
            return (id, written)
        }.sorted { $0.written < $1.written }
        // New pages take the paper of the one before them, as pages added in the editor do.
        let paper = manifest.pages.last { $0.pdfPageIndex == nil }?.background ?? .blank
        manifest.pages += orphans.map { PageInfo(id: $0.id, background: paper) }
        return orphans.count
    }

    func saveManifest(_ manifest: NotebookManifest) throws {
        let data = try Self.encoder.encode(manifest)
        backUpManifest(for: manifest.id)
        try data.write(to: manifestURL(for: manifest.id), options: .atomic)
    }

    /// Copies the manifest on disk to `manifest.prev.json` before it is replaced, but only if it is valid, so a
    /// damaged file never overwrites a good backup. Best effort: a failed backup must not stop the save itself.
    private func backUpManifest(for notebookID: UUID) {
        guard let current = try? Data(contentsOf: manifestURL(for: notebookID)),
              (try? Self.decoder.decode(NotebookManifest.self, from: current)) != nil else { return }
        try? current.write(to: previousManifestURL(for: notebookID), options: .atomic)
    }

    /// Renames a damaged file to `<name>.corrupt` (`.corrupt-2`, … if taken) and returns the new URL.
    @discardableResult
    private func quarantine(_ url: URL) throws -> URL {
        let fileManager = FileManager.default
        var target = url.appendingPathExtension("corrupt")
        var attempt = 1
        while fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            attempt += 1
            target = url.appendingPathExtension("corrupt-\(attempt)")
        }
        try fileManager.moveItem(at: url, to: target)
        return target
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
        try loadDrawingReport(pageID: pageID, notebookID: notebookID).drawing
    }

    /// Like `loadDrawing`, but a damaged file is set aside and the page opens empty, so one bad page never stops a
    /// notebook from opening. If the file can't be set aside this throws, rather than risk a later save replacing it.
    func loadDrawingReport(pageID: UUID, notebookID: UUID) throws -> DrawingLoad {
        let url = drawingURL(pageID: pageID, notebookID: notebookID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return DrawingLoad(drawing: PKDrawing())
        }
        let data = try Data(contentsOf: url)
        if let drawing = try? Self.decodeDrawing(data) { return DrawingLoad(drawing: drawing) }
        let moved = try quarantine(url)
        return DrawingLoad(drawing: PKDrawing(), notices: [
            "A page's ink couldn't be read. The damaged file was kept as pages/\(moved.lastPathComponent)."
        ])
    }

    /// PencilKit turns data without its format header into an empty drawing instead of throwing, so an empty result
    /// only counts as valid when the header is there.
    static func decodeDrawing(_ data: Data) throws -> PKDrawing {
        let drawing = try PKDrawing(data: data)
        if drawing.strokes.isEmpty, !data.starts(with: drawingHeader) {
            throw CocoaError(.fileReadCorruptFile)
        }
        return drawing
    }

    /// The first bytes of `PKDrawing.dataRepresentation()` ("wrd").
    static let drawingHeader: [UInt8] = [0x77, 0x72, 0x64]

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
