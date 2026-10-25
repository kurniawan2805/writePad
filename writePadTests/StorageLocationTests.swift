import Foundation
import Testing
@testable import writePad

struct StorageLocationTests {
    @Test func defaultsToDocumentsAndTheDefaultLibraryStore() throws {
        let location = try StorageLocation.current(environment: [:])
        #expect(location.notebooksURL == URL.documentsDirectory)
        #expect(location.libraryStoreURL == nil)
    }

    @Test func uiTestNamespaceIsSeparateAndClearsEarlierRuns() throws {
        let stale = try StorageLocation.current(environment: [StorageLocation.namespaceKey: "stale-\(UUID())"])
        let location = try StorageLocation.current(environment: [StorageLocation.namespaceKey: "run-\(UUID())"])

        #expect(location.notebooksURL.path(percentEncoded: false).contains("/UITests/run-"))
        #expect(location.notebooksURL != URL.documentsDirectory)
        #expect(FileManager.default.fileExists(atPath: location.notebooksURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: stale.notebooksURL.path(percentEncoded: false)))
        _ = try location.makeContainer()
    }
}
