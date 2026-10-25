import Foundation
import SwiftData

/// Where notebooks and the library index live.
///
/// UI tests launch Debug builds with `WRITEPAD_STORAGE_NAMESPACE` set, which moves all data into
/// `Application Support/UITests/<namespace>/` so tests never touch real notebooks or each other,
/// while relaunches within one test still see the same data.
struct StorageLocation {
    static let namespaceKey = "WRITEPAD_STORAGE_NAMESPACE"

    let notebooksURL: URL
    let libraryStoreURL: URL?

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> StorageLocation {
        #if DEBUG
        if let namespace = environment[namespaceKey], !namespace.isEmpty {
            return try uiTest(namespace: namespace)
        }
        #endif
        return StorageLocation(notebooksURL: .documentsDirectory, libraryStoreURL: nil)
    }

    func makeContainer() throws -> ModelContainer {
        let configuration = libraryStoreURL.map { ModelConfiguration(url: $0) } ?? ModelConfiguration()
        return try ModelContainer(for: LibraryNotebook.self, LibraryFolder.self, configurations: configuration)
    }

    private static func uiTest(namespace: String) throws -> StorageLocation {
        let testsRoot = URL.applicationSupportDirectory.appending(path: "UITests", directoryHint: .isDirectory)
        let root = testsRoot.appending(path: namespace, directoryHint: .isDirectory)
        // Leftovers from earlier test runs (including failed ones) are removed on the next launch.
        let others = (try? FileManager.default.contentsOfDirectory(at: testsRoot, includingPropertiesForKeys: nil)) ?? []
        for url in others where url.lastPathComponent != namespace {
            try? FileManager.default.removeItem(at: url)
        }
        let notebooks = root.appending(path: "Notebooks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: notebooks, withIntermediateDirectories: true)
        return StorageLocation(notebooksURL: notebooks, libraryStoreURL: root.appending(path: "Library.store"))
    }
}
