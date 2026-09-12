import XCTest

final class StudioUITests: XCTestCase {
    @MainActor private func launchStudio() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let storageAlert = app.alerts["ReyWidgets"]
        XCTAssertFalse(storageAlert.waitForExistence(timeout: 2), storageAlert.debugDescription)
        return app
    }
    @MainActor func testCreateNativeWidgetOpensEditor() throws {
        let app = launchStudio()
        XCTAssertTrue(app.buttons["studio.create"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["studio.create"].isEnabled, "Shared storage must be available before creating a widget.")
        app.buttons["studio.create"].tap()
        let name = app.textFields["design.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "My widget".count) + "UI test widget")
        app.buttons["design.create"].tap()
        XCTAssertTrue(app.buttons["Run preview"].waitForExistence(timeout: 5) || app.navigationBars["UI test widget"].exists)
    }
    @MainActor func testSettingsAndGGUFImportAreDiscoverable() throws {
        let app = launchStudio()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Local intelligence"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Import .gguf from Files"].exists)
    }
}
