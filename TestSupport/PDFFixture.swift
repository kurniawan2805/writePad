import Foundation

enum PDFFixture {
    static func data(pageCount: Int = 2, rotation: Int = 0) -> Data {
        let pageNumbers = (0..<pageCount).map { 6 + $0 * 2 }
        let destination = pageNumbers[min(1, pageCount - 1)]
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 4 0 R >>",
            "<< /Type /Pages /Count \(pageCount) /Kids [\(pageNumbers.map { "\($0) 0 R" }.joined(separator: " "))] >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Outlines /First 5 0 R /Last 5 0 R /Count 1 >>",
            "<< /Title (Chapter Two) /Parent 4 0 R /Dest [\(destination) 0 R /Fit] >>",
        ]
        for (index, number) in pageNumbers.enumerated() {
            let text = "BT /F1 24 Tf 72 650 Td (Lecture \(index + 1) - searchable text) Tj ET"
            objects.append("""
            << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Rotate \(index == 0 ? rotation : 0)
            /Resources << /Font << /F1 3 0 R >> >> /Contents \(number + 1) 0 R >>
            """)
            objects.append("<< /Length \(text.utf8.count) >>\nstream\n\(text)\nendstream")
        }
        var output = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(output.utf8.count)
            output += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = output.utf8.count
        output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { output += String(format: "%010d 00000 n \n", offset) }
        output += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(output.utf8)
    }
}
