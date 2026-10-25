import Foundation

struct PageItem: Codable, Equatable, Identifiable, Sendable {
    enum Content: Codable, Equatable, Sendable {
        case text(String, fontSize: Double)
        case image(UUID)
    }

    var id = UUID()
    var frame: CGRect
    var content: Content

    func fitted(to size: CGSize) -> Self {
        var copy = self
        let width = min(max(frame.width.isFinite ? frame.width : 120, 32), size.width)
        let height = min(max(frame.height.isFinite ? frame.height : 60, 32), size.height)
        copy.frame = CGRect(x: min(max(frame.origin.x.isFinite ? frame.origin.x : 0, 0), size.width - width),
                            y: min(max(frame.origin.y.isFinite ? frame.origin.y : 0, 0), size.height - height),
                            width: width, height: height)
        if case let .text(text, fontSize) = content {
            copy.content = .text(text, fontSize: min(max(fontSize.isFinite ? fontSize : 24, 8), 144))
        }
        return copy
    }
}
