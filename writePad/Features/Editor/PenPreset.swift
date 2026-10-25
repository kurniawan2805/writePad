import PencilKit
import UIKit

struct PenPreset: Codable, Equatable, Identifiable {
    enum Ink: String, Codable, CaseIterable {
        case pen, pencil, marker, monoline

        var type: PKInkingTool.InkType {
            switch self {
            case .pen: .pen
            case .pencil: .pencil
            case .marker: .marker
            case .monoline: .monoline
            }
        }
    }

    struct RGBA: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double = 1

        var isValid: Bool { [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
        var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }

        init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        init(_ color: UIColor) {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.init(red: red, green: green, blue: blue, alpha: alpha)
        }
    }

    var id = UUID()
    var ink = Ink.pen
    var width: Double = 3
    var color = RGBA(red: 0, green: 0, blue: 0)

    var isValid: Bool { width.isFinite && (0.5...30).contains(width) && color.isValid }
    var tool: PKInkingTool { PKInkingTool(ink.type, color: color.uiColor, width: width) }
}
