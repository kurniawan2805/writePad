import Foundation
import UIKit

extension NotebookStore {
    func itemsURL(pageID: UUID, revision: UUID, notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: "pages/\(pageID).items-\(revision).json")
    }

    func imageURL(assetID: UUID, notebookID: UUID) -> URL {
        packageURL(for: notebookID).appending(path: "images/\(assetID).png")
    }

    func recoveredPage(id: UUID, background: PageBackground, files: [URL]) -> PageInfo {
        var page = PageInfo(id: id, background: background)
        page.itemsRevision = latestItemsRevision(pageID: id, files: files)
        return page
    }

    // Recover item content too when an orphan drawing restores a newly added page after a crash.
    private func latestItemsRevision(pageID: UUID, files: [URL]) -> UUID? {
        let prefix = "\(pageID).items-"
        return files.compactMap { url -> (UUID, Date)? in
            guard url.pathExtension == "json", url.lastPathComponent.hasPrefix(prefix),
                  let revision = UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.dropFirst(prefix.count))),
                  let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (revision, date)
        }.max { $0.1 < $1.1 }?.0
    }

    func loadItems(page: PageInfo, notebookID: UUID) throws -> [PageItem] {
        guard let revision = page.itemsRevision else { return [] }
        let data = try Data(contentsOf: itemsURL(pageID: page.id, revision: revision, notebookID: notebookID))
        let items = try JSONDecoder().decode([PageItem].self, from: data)
        guard Set(items.map(\.id)).count == items.count else { throw CocoaError(.fileReadCorruptFile) }
        for item in items {
            let frame = item.frame
            guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
                  frame.size.width > 0, frame.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
            if case let .text(_, size) = item.content, !size.isFinite || !(8...144).contains(size) {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return items
    }

    func loadImage(assetID: UUID, notebookID: UUID) throws -> Data {
        let data = try Data(contentsOf: imageURL(assetID: assetID, notebookID: notebookID))
        guard UIImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    func writePageItems(_ snapshot: SaveSnapshot) throws {
        try ensureWritable(snapshot.manifest.id)
        for (id, data) in snapshot.imageAssets {
            try writeImmutable(data, to: imageURL(assetID: id, notebookID: snapshot.manifest.id))
        }
        for page in snapshot.manifest.pages {
            guard let revision = page.itemsRevision, let items = snapshot.pageItems[page.id] else { continue }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(items)
            try writeImmutable(data, to: itemsURL(pageID: page.id, revision: revision, notebookID: snapshot.manifest.id))
        }
    }

    private func writeImmutable(_ data: Data, to url: URL) throws {
        // A revision may already have reached disk before a failed manifest write.
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteFileExists) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
