import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, 1])!
}

for dark in [false, true] {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(dark ? color(0.06, 0.12, 0.16) : color(0.08, 0.32, 0.38))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    context.saveGState()
    context.translateBy(x: 512, y: 512)
    context.rotate(by: -.pi / 28)
    let paper = CGRect(x: -280, y: -326, width: 560, height: 652)
    context.setShadow(offset: CGSize(width: 0, height: 16), blur: 36, color: color(0.03, 0.08, 0.10).copy(alpha: 0.3))
    context.setFillColor(color(0.98, 0.97, 0.93))
    context.addPath(CGPath(roundedRect: paper, cornerWidth: 40, cornerHeight: 40, transform: nil))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0)
    context.setFillColor(color(0.37, 0.81, 0.72))
    context.fill(CGRect(x: -280, y: -280, width: 38, height: 560))

    context.setStrokeColor(color(0.78, 0.83, 0.82))
    context.setLineWidth(6)
    context.setLineCap(.round)
    for y in stride(from: -190, through: 218, by: 102) {
        context.move(to: CGPoint(x: -168, y: y))
        context.addLine(to: CGPoint(x: 186, y: y))
    }
    context.strokePath()

    context.setStrokeColor(color(0.08, 0.27, 0.32))
    context.setLineWidth(27)
    context.move(to: CGPoint(x: -150, y: 15))
    context.addCurve(to: CGPoint(x: -64, y: 72), control1: CGPoint(x: -112, y: 150), control2: CGPoint(x: -112, y: 172))
    context.addCurve(to: CGPoint(x: 10, y: 128), control1: CGPoint(x: -12, y: -45), control2: CGPoint(x: -8, y: 120))
    context.addCurve(to: CGPoint(x: 148, y: -44), control1: CGPoint(x: 42, y: 170), control2: CGPoint(x: 106, y: 34))
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: 740, y: 622)
    context.rotate(by: .pi / 5)
    context.setFillColor(color(0.37, 0.81, 0.72))
    context.addPath(CGPath(roundedRect: CGRect(x: -33, y: -232, width: 66, height: 310),
                           cornerWidth: 20, cornerHeight: 20, transform: nil))
    context.fillPath()
    context.setFillColor(color(0.98, 0.97, 0.93))
    context.move(to: CGPoint(x: -33, y: 55))
    context.addLine(to: CGPoint(x: 33, y: 55))
    context.addLine(to: CGPoint(x: 0, y: 132))
    context.closePath()
    context.fillPath()
    context.setFillColor(color(0.08, 0.27, 0.32))
    context.move(to: CGPoint(x: -12, y: 104))
    context.addLine(to: CGPoint(x: 12, y: 104))
    context.addLine(to: CGPoint(x: 0, y: 132))
    context.closePath()
    context.fillPath()
    context.restoreGState()

    let filename = dark ? "AppIcon-Dark.png" : "AppIcon.png"
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename), options: .atomic)
}
