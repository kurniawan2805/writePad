import XCTest

extension XCUIApplication {
    /// An app whose notebooks and library live in a fresh namespace (see `StorageLocation`).
    /// Relaunching the same instance keeps that data; other tests and real notebooks are untouched.
    static func isolated() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WRITEPAD_STORAGE_NAMESPACE"] = UUID().uuidString
        return app
    }

    func pageIndicator(_ current: Int, of total: Int) -> XCUIElement {
        buttons.matching(identifier: "Pages")
            .matching(NSPredicate(format: "value == %@", "Page \(current) of \(total)"))
            .firstMatch
    }
}
