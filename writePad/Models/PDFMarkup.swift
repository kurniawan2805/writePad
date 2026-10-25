import Foundation
import PDFKit

struct PDFMarkup: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case highlight, underline, strikeOut, comment

        var subtype: PDFAnnotationSubtype {
            switch self {
            case .highlight: .highlight
            case .underline: .underline
            case .strikeOut: .strikeOut
            case .comment: .text
            }
        }

        var actionName: String {
            switch self {
            case .highlight: "Highlight"
            case .underline: "Underline"
            case .strikeOut: "Strikethrough"
            case .comment: "Comment"
            }
        }
    }

    var id = UUID()
    var pageID: UUID
    var kind: Kind
    var bounds: CGRect
    var text: String = ""

    func annotation() -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: kind.subtype, withProperties: nil)
        annotation.userName = "writePad"
        annotation.contents = text
        annotation.color = kind == .highlight || kind == .comment ? .systemYellow : .systemRed
        if kind == .comment { annotation.iconType = .comment }
        return annotation
    }
}
