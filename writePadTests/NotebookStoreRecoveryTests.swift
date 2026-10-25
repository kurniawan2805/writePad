import Foundation
import PencilKit
import Testing
@testable import writePad

/// Damaged files and pages left behind by a crashed save: what `NotebookStore` sets aside, restores or recovers.
struct NotebookStoreRecoveryTests {
    let store: NotebookStore

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NotebookStore(rootURL: root)
    }

    // MARK: Damaged files

    private func manifestURL(_ id: UUID) -> URL { store.packageURL(for: id).appending(path: "manifest.json") }
    private func backupURL(_ id: UUID) -> URL { store.packageURL(for: id).appending(path: "manifest.prev.json") }
    private func title(at url: URL) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return object?["title"] as? String
    }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// A notebook saved twice, so `manifest.prev.json` holds the first title.
    private func notebookWithBackup() throws -> NotebookManifest {
        var manifest = try store.createNotebook(title: "First")
        manifest.title = "Second"
        try store.saveManifest(manifest)
        return manifest
    }

    @Test func savingKeepsThePreviousManifestAsBackup() throws {
        let manifest = try notebookWithBackup()

        #expect(try title(at: backupURL(manifest.id)) == "First")
        #expect(try store.loadManifest(id: manifest.id).title == "Second")
    }

    @Test func firstSaveWritesNoBackup() throws {
        let manifest = try store.createNotebook(title: "Only")
        #expect(!exists(backupURL(manifest.id)))
    }

    @Test func damagedManifestFallsBackToBackupAndIsKept() throws {
        let manifest = try notebookWithBackup()
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: manifestURL(manifest.id))

        let load = try store.loadManifestReport(id: manifest.id)

        #expect(load.manifest.title == "First")
        #expect(!load.notices.isEmpty)
        let kept = manifestURL(manifest.id).appendingPathExtension("corrupt")
        #expect(try Data(contentsOf: kept) == garbage)
        // The backup was put back, so a plain load now works and shows the same notebook.
        #expect(try store.loadManifest(id: manifest.id).title == "First")
        #expect(try store.loadManifestReport(id: manifest.id).notices.isEmpty)
    }

    @Test func missingManifestFallsBackToBackup() throws {
        let manifest = try notebookWithBackup()
        try FileManager.default.removeItem(at: manifestURL(manifest.id))

        #expect(try store.loadManifest(id: manifest.id).title == "First")
        #expect(exists(manifestURL(manifest.id)))
    }

    @Test func unreadableManifestIsNotReplacedByTheOlderBackup() throws {
        let manifest = try notebookWithBackup()
        let url = manifestURL(manifest.id)
        // Present but unreadable, like a passing I/O or data-protection error: not damage.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false)) }

        #expect(throws: (any Error).self) { try store.loadManifestReport(id: manifest.id) }

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))
        #expect(try title(at: url) == "Second")
        #expect(!exists(url.appendingPathExtension("corrupt")))
    }

    @Test func damagedManifestWithoutBackupThrowsAndKeepsTheFile() throws {
        let manifest = try store.createNotebook(title: "Alone")
        let garbage = Data("garbage".utf8)
        try garbage.write(to: manifestURL(manifest.id))

        #expect(throws: NotebookStore.StoreError.corruptManifest(setAside: ["manifest.json.corrupt"])) {
            try store.loadManifest(id: manifest.id)
        }
        #expect(try Data(contentsOf: manifestURL(manifest.id).appendingPathExtension("corrupt")) == garbage)
        #expect(try store.listNotebooks().isEmpty)
    }

    @Test func secondDamagedManifestDoesNotReplaceTheFirstKeptCopy() throws {
        let manifest = try store.createNotebook(title: "Twice")
        try Data("first".utf8).write(to: manifestURL(manifest.id))
        _ = try? store.loadManifest(id: manifest.id)
        try Data("second".utf8).write(to: manifestURL(manifest.id))
        _ = try? store.loadManifest(id: manifest.id)

        let base = manifestURL(manifest.id)
        #expect(try Data(contentsOf: base.appendingPathExtension("corrupt")) == Data("first".utf8))
        #expect(try Data(contentsOf: base.appendingPathExtension("corrupt-2")) == Data("second".utf8))
    }

    @Test func damagedManifestDoesNotOverwriteAGoodBackupOnSave() throws {
        var manifest = try notebookWithBackup()
        try Data("garbage".utf8).write(to: manifestURL(manifest.id))

        manifest.title = "Third"
        try store.saveManifest(manifest)

        #expect(try title(at: backupURL(manifest.id)) == "First")
    }

    @Test func newerManifestIsNeitherSetAsideNorReplacedByTheBackup() throws {
        var manifest = try notebookWithBackup()
        manifest.version = NotebookManifest.currentVersion + 1
        try store.saveManifest(manifest)
        let before = try Data(contentsOf: manifestURL(manifest.id))

        #expect(throws: NotebookStore.StoreError.unsupportedVersion(manifest.version)) {
            try store.loadManifest(id: manifest.id)
        }
        #expect(try Data(contentsOf: manifestURL(manifest.id)) == before)
        #expect(!exists(manifestURL(manifest.id).appendingPathExtension("corrupt")))
    }

    @Test func damagedDrawingIsSetAsideAndThePageOpensEmpty() throws {
        let manifest = try store.createNotebook(title: "Ink")
        let pageID = manifest.pages[0].id
        try store.saveDrawing(NotebookStoreTests.sampleDrawing(), pageID: pageID, notebookID: manifest.id)
        let file = store.packageURL(for: manifest.id).appending(path: "pages/\(pageID.uuidString).drawing")
        let garbage = Data("this is not a drawing".utf8)
        try garbage.write(to: file)

        let load = try store.loadDrawingReport(pageID: pageID, notebookID: manifest.id)

        #expect(load.drawing.strokes.isEmpty)
        #expect(!load.notices.isEmpty)
        #expect(!exists(file))
        #expect(try Data(contentsOf: file.appendingPathExtension("corrupt")) == garbage)
    }

    @Test func emptyDrawingWithItsHeaderIsNotDamage() throws {
        let manifest = try store.createNotebook(title: "Blank")
        let pageID = manifest.pages[0].id
        try store.saveDrawing(PKDrawing(), pageID: pageID, notebookID: manifest.id)

        let load = try store.loadDrawingReport(pageID: pageID, notebookID: manifest.id)

        #expect(load.notices.isEmpty)
        #expect(load.drawing.strokes.isEmpty)
    }

    @Test func drawingDataStartsWithTheHeaderTheCheckLooksFor() {
        #expect(PKDrawing().dataRepresentation().starts(with: NotebookStore.drawingHeader))
        #expect(NotebookStoreTests.sampleDrawing().dataRepresentation().starts(with: NotebookStore.drawingHeader))
        #expect(throws: (any Error).self) { try NotebookStore.decodeDrawing(Data("nope".utf8)) }
    }

    // MARK: Pages left by a crashed save

    /// Writes a drawing for a page the manifest doesn't list, stamped `offset` seconds after the manifest's last save.
    @discardableResult
    private func writeOrphan(for manifest: NotebookManifest, offset: TimeInterval, data: Data? = nil) throws -> UUID {
        let pageID = UUID()
        let file = store.packageURL(for: manifest.id).appending(path: "pages/\(pageID.uuidString).drawing")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data ?? NotebookStoreTests.sampleDrawing().dataRepresentation()).write(to: file)
        let written = manifest.updatedAt.addingTimeInterval(offset)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: file.path(percentEncoded: false))
        return pageID
    }

    @Test func drawingNewerThanTheManifestIsRecoveredAsAPage() throws {
        let manifest = try store.createNotebook(title: "Crashed", background: .grid)
        let orphan = try writeOrphan(for: manifest, offset: 5)

        let load = try store.loadManifestReport(id: manifest.id)

        #expect(load.manifest.pages.map(\.id) == [manifest.pages[0].id, orphan])
        #expect(load.manifest.pages[1].background == .grid, "the recovered page takes the paper of the one before it")
        #expect(load.needsSave)
        #expect(!load.notices.isEmpty)
        #expect(try store.loadDrawing(pageID: orphan, notebookID: manifest.id).strokes.count == 1)
    }

    @Test func drawingOlderThanTheManifestIsAPageDeletedOnPurposeAndIsNotRecovered() throws {
        let manifest = try store.createNotebook(title: "Deleted")
        try writeOrphan(for: manifest, offset: -5)

        let load = try store.loadManifestReport(id: manifest.id)

        #expect(load.manifest.pages.count == 1)
        #expect(!load.needsSave)
        #expect(load.notices.isEmpty)
    }

    @Test func undecodableNewerDrawingIsLeftAloneAndNotRecovered() throws {
        let manifest = try store.createNotebook(title: "Junk")
        let orphan = try writeOrphan(for: manifest, offset: 5, data: Data("junk".utf8))

        let load = try store.loadManifestReport(id: manifest.id)

        #expect(load.manifest.pages.count == 1)
        #expect(exists(store.packageURL(for: manifest.id).appending(path: "pages/\(orphan.uuidString).drawing")))
    }

    @Test func listingDoesNotScanForPages() throws {
        let manifest = try store.createNotebook(title: "Listed")
        try writeOrphan(for: manifest, offset: 5)

        #expect(try store.loadManifest(id: manifest.id).pages.count == 1)
        #expect(try store.listNotebooks().first?.pages.count == 1)
    }

    @Test func recoveredPagesAreFoundAgainUntilTheManifestIsSaved() throws {
        let manifest = try store.createNotebook(title: "Twice")
        try writeOrphan(for: manifest, offset: 5)

        var first = try store.loadManifestReport(id: manifest.id)
        #expect(first.manifest.pages.count == 2)
        try store.saveManifest(first.manifest)
        first = try store.loadManifestReport(id: manifest.id)

        #expect(first.manifest.pages.count == 2)
        #expect(first.notices.isEmpty, "once saved, the page is listed and nothing is recovered again")
    }
}
