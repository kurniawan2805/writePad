import Foundation
import Observation

/// Process-wide ownership: a failed flush must keep both the ink and its write lock alive.
@MainActor
@Observable
final class NotebookAccessRegistry {
    static let shared = NotebookAccessRegistry()

    private struct Writer {
        let editor: EditorViewModel
        var isConnected = true
    }

    private var writers: [URL: Writer] = [:]
    private(set) var libraryVersion = 0

    func libraryDidChange() { libraryVersion += 1 }

    func prepareToOpen(_ url: URL) throws -> Bool {
        let key = url.standardizedFileURL
        guard let writer = writers[key] else { return true }
        if writer.isConnected { writer.editor.saveNow() } else { writer.editor.closeIfSaved() }
        if let error = writer.editor.lastError { throw AccessError.saveFailed(error) }
        if !writer.isConnected {
            writers[key] = nil
            return true
        }
        return false
    }

    func register(_ editor: EditorViewModel) {
        guard !editor.isReadOnly else { return }
        let key = editor.store.packageURL(for: editor.manifest.id).standardizedFileURL
        precondition(writers[key] == nil)
        writers[key] = Writer(editor: editor)
    }

    func release(_ editor: EditorViewModel, disconnected: Bool = false) {
        let key = editor.store.packageURL(for: editor.manifest.id).standardizedFileURL
        guard writers[key]?.editor === editor else { return }
        if editor.lastError == nil {
            writers[key] = nil
        } else if disconnected {
            writers[key]?.isConnected = false
        }
    }

    func ensureClosed(_ url: URL) throws {
        guard writers[url.standardizedFileURL] == nil else { throw AccessError.openInWindow }
    }

    enum AccessError: LocalizedError {
        case openInWindow
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .openInWindow: "Close this notebook in its other window before renaming or deleting it."
            case let .saveFailed(message): "The other window couldn't save this notebook: \(message)"
            }
        }
    }
}
