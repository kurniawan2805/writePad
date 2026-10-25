import Foundation
import UIKit

/// A long PDF for scale tests. Set `WRITEPAD_LARGE_PDF` (for UI tests: `TEST_RUNNER_WRITEPAD_LARGE_PDF`) to a real
/// document's path; otherwise a 120-page book with text and images is generated once per run.
enum LargePDF {
    static let environmentKey = "WRITEPAD_LARGE_PDF"
    static let generatedPageCount = 120

    static func url() throws -> URL {
        if let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(filePath: path)
        }
        let url = URL.temporaryDirectory.appending(path: "writePad Large Fixture v3.pdf")
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try generate(to: url)
        }
        return url
    }

    /// A word any long English document contains, for search tests.
    static let searchTerm = "the"

    private static func generate(to url: URL) throws {
        let size = CGSize(width: 612, height: 792)
        let body = String(repeating: """
            Handwritten notes and a notebook full of diagrams sit next to the lecture slides. Each paragraph is long \
            enough to wrap over several lines so the page has real text layout, fonts and searchable words. \

            """, count: 6)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            for index in 0..<generatedPageCount {
                context.beginPage()
                let title = index.isMultiple(of: 10) ? "Chapter \(index / 10 + 1)" : "Section \(index + 1)"
                NSAttributedString(string: title, attributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
                    .draw(at: CGPoint(x: 72, y: 72))
                NSAttributedString(string: "Page \(index + 1), \(topic(index)). " + body, attributes: [.font: UIFont.systemFont(ofSize: 12)])
                    .draw(in: CGRect(x: 72, y: 120, width: size.width - 144, height: 420))
                if index.isMultiple(of: 5) {
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 120)).image { image in
                        UIColor(hue: CGFloat(index % 12) / 12, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
                        image.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
                    }
                    image.draw(in: CGRect(x: 72, y: 560, width: 200, height: 120))
                }
            }
        }
        try data.write(to: url, options: .atomic)
    }

    /// A word found on one page only, like "Topicaab", so a search can jump to that page.
    private static func topic(_ index: Int) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return "Topic" + String([letters[index / 676 % 26], letters[index / 26 % 26], letters[index % 26]])
    }
}
