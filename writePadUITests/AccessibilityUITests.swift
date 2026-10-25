import UIKit
import XCTest

@MainActor
final class AccessibilityUITests: XCTestCase {
    func testLightAppearance() throws { try audit(appearance: "Light") }
    func testDarkAppearance() throws { try audit(appearance: "Dark") }
    func testLargestTextInLightAppearance() throws { try audit(appearance: "Light", largestText: true) }
    func testLargestTextInDarkAppearance() throws { try audit(appearance: "Dark", largestText: true) }

    private func audit(appearance: String, largestText: Bool = false) throws {
        continueAfterFailure = true
        let app = XCUIApplication.isolated()
        app.launchEnvironment["WRITEPAD_TEST_APPEARANCE"] = appearance
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = appearance == "Dark" ? .dark : .light
        defer {
            app.terminate()
            XCUIDevice.shared.appearance = previousAppearance
        }
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["Create"].waitForExistence(timeout: 15))
        app.buttons["Create"].tap()
        app.buttons["New Notebook"].firstMatch.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Accessibility Notes")
        app.buttons["Save"].tap()
        let url = URL.temporaryDirectory.appending(path: "Accessibility PDF \(UUID().uuidString).pdf")
        try PDFFixture.data().write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        app.open(url)
        let pdf = app.buttons.containing(.staticText, identifier: url.deletingPathExtension().lastPathComponent).firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 15))
        try assertRenderedAppearance(appearance, in: app)
        try auditSurface("Library", in: app)
        app.buttons.containing(.staticText, identifier: "Accessibility Notes").firstMatch.tap()
        XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 5))
        try auditSurface("Notebook", in: app, nativeTitle: "Accessibility Notes")
        app.buttons["Library"].tap()
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        pdf.tap()
        XCTAssertTrue(app.buttons["PDF Tools"].waitForExistence(timeout: 5))
        try auditSurface("PDF", in: app, nativeTitle: url.deletingPathExtension().lastPathComponent)
    }

    private func assertRenderedAppearance(_ appearance: String, in app: XCUIApplication) throws {
        let image = try XCTUnwrap(UIImage(data: app.screenshot().pngRepresentation)?.cgImage)
        // The library's left margin is blank sidebar background at every supported text size.
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: 4, y: image.height / 2, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                 bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertEqual(pixel.prefix(3).allSatisfy { $0 < 128 }, appearance == "Dark",
                       "Expected \(appearance) sidebar rendering; sampled RGBA \(pixel)")
    }

    private func auditSurface(_ name: String, in app: XCUIApplication, nativeTitle: String? = nil) throws {
        try XCTContext.runActivity(named: "Audit \(name)") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
            try app.performAccessibilityAudit { issue in
                // PencilKit owns this visual handle and its gesture region; the app cannot resize it.
                if issue.auditType == .hitRegion, issue.element?.label == "Tool palette handle" { return true }
                // UIKit's single-line navigation title truncates visually, but VoiceOver speaks its full label.
                // The full editable title is also available on the library card; do not exclude card text.
                if issue.auditType == .textClipped, let nativeTitle, issue.element?.label == nativeTitle,
                   app.navigationBars.staticTexts[nativeTitle].exists { return true }
                print("Accessibility: \(issue.compactDescription); \(issue.detailedDescription); \(String(describing: issue.element))")
                return false
            }
        }
    }
}
