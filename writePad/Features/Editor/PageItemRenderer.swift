import UIKit

enum PageItemRenderer {
    static func draw(_ items: [PageItem], assets: [UUID: Data], in context: CGContext) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        for item in items {
            context.saveGState()
            context.clip(to: item.frame)
            switch item.content {
            case let .text(text, fontSize):
                (text as NSString).draw(in: item.frame, withAttributes: [
                    .font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.black
                ])
            case let .image(id):
                if let data = assets[id], let image = UIImage(data: data) {
                    let scale = min(item.frame.width / image.size.width, item.frame.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: item.frame.midX - size.width / 2, y: item.frame.midY - size.height / 2,
                                          width: size.width, height: size.height))
                }
            }
            context.restoreGState()
        }
    }
}
