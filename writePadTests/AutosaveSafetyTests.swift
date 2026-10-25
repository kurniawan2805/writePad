import Foundation
import PencilKit
import Testing
@testable import writePad

@MainActor
struct AutosaveSafetyTests {
    @Test func failedManifestSaveDoesNotDeletePersistedInk() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = NotebookStore(rootURL: root)
        let editor = try EditorViewModel.openDefault(store: store)
        editor.addPage()
        let pageID = editor.pages[1].id
        editor.drawingDidChange(PageLayout(pageCount: 2).merge([PKDrawing(), NotebookStoreTests.sampleDrawing()]))
        editor.saveNow()
        let manifestURL = store.packageURL(for: editor.manifest.id).appending(path: "manifest.json")
        let savedManifest = try Data(contentsOf: manifestURL)
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)

        editor.deletePage(at: 1)
        editor.saveNow()

        #expect(editor.lastError != nil)
        #expect(try store.loadDrawing(pageID: pageID, notebookID: editor.manifest.id).strokes.count == 1)
        try FileManager.default.removeItem(at: manifestURL)
        try savedManifest.write(to: manifestURL, options: .atomic)
        #expect(try store.loadManifest(id: editor.manifest.id).pages.count == 2)
        editor.saveNow()
        #expect(editor.lastError == nil)
        #expect(try store.loadManifest(id: editor.manifest.id).pages.count == 1)
        #expect(try store.loadDrawing(pageID: pageID, notebookID: editor.manifest.id).strokes.isEmpty)
    }

    // MARK: Timing rules

    @Test func saveStartsWithinMaxLatencyHoweverOftenEditsArrive() {
        let timing = SaveTiming()
        let start = ContinuousClock.now
        let firstEdit = start
        let nearTheCap = start + .seconds(4.9)

        #expect(timing.deadline(now: start, firstUnsaved: firstEdit) == start + .seconds(1))
        #expect(timing.deadline(now: nearTheCap, firstUnsaved: firstEdit) == start + .seconds(5))
    }

    @Test func changesDuringBackoffDoNotRetrySooner() {
        let timing = SaveTiming()
        let now = ContinuousClock.now
        let backoffEnds = now + .seconds(30)

        #expect(timing.deadline(now: now, firstUnsaved: now, notBefore: backoffEnds) == backoffEnds)
        #expect(timing.deadline(now: now, firstUnsaved: now, notBefore: now - .seconds(1)) == now + .seconds(1))
    }

    @Test func retryDelayDoublesAndStopsAtTheCap() {
        let timing = SaveTiming()
        let delays = (1...8).map { timing.retryDelay(afterFailures: $0) }

        #expect(delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60), .seconds(60)])
    }

    // MARK: Autosave behavior

    /// Polls until `condition` holds or `seconds` pass; the autosave tasks run on the main actor between polls.
    private func wait(upTo seconds: Double = 5, until condition: () -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(seconds)
        while !condition(), ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(20)) }
    }

    private func inkFileCount(_ store: NotebookStore, _ editor: EditorViewModel) -> Int {
        let pages = store.packageURL(for: editor.manifest.id).appending(path: "pages")
        return ((try? FileManager.default.contentsOfDirectory(atPath: pages.path(percentEncoded: false))) ?? []).count
    }

    @Test func continuousWritingIsSavedBeforeThePenPauses() async throws {
        let store = NotebookStore(rootURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let editor = try EditorViewModel.openDefault(store: store)
        editor.saveTiming = SaveTiming(delay: .milliseconds(300), maxLatency: .milliseconds(700))
        let pageID = editor.pages[0].id
        let stroke = try #require(NotebookStoreTests.sampleDrawing().strokes.first)

        // A stroke every 100 ms never leaves the 300 ms quiet time the plain debounce needs.
        for count in 1...12 {
            editor.drawingDidChange(PKDrawing(strokes: Array(repeating: stroke, count: count)), pageID: pageID)
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(inkFileCount(store, editor) == 1, "nothing reached disk while the pen kept moving")
        #expect(try store.loadDrawing(pageID: pageID, notebookID: editor.manifest.id).strokes.count >= 1)
    }

    @Test func failedSaveRetriesByItselfAndKeepsTheInk() async throws {
        let store = NotebookStore(rootURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let editor = try EditorViewModel.openDefault(store: store)
        editor.saveTiming = SaveTiming(delay: .milliseconds(30), maxLatency: .milliseconds(200),
                                       retryBase: .milliseconds(60), retryCap: .milliseconds(240))
        let pageID = editor.pages[0].id
        let manifestURL = store.packageURL(for: editor.manifest.id).appending(path: "manifest.json")
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false) // the manifest write now fails

        editor.drawingDidChange(NotebookStoreTests.sampleDrawing(), pageID: pageID)
        try await wait { editor.lastError != nil }
        #expect(editor.lastError != nil)

        // Let a couple of backed-off retries fail, then make the write possible again.
        try await Task.sleep(for: .milliseconds(300))
        #expect(editor.lastError != nil)
        try FileManager.default.removeItem(at: manifestURL)
        try await wait { editor.lastError == nil }

        #expect(editor.lastError == nil, "the retry succeeded without anyone calling saveNow")
        #expect(try store.loadManifest(id: editor.manifest.id).id == editor.manifest.id)
        #expect(try store.loadDrawing(pageID: pageID, notebookID: editor.manifest.id).strokes.count == 1)
    }
}
