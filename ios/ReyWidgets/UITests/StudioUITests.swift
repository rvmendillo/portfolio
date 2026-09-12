import XCTest

final class StudioUITests: XCTestCase {
    @MainActor func testCreateNativeWidgetOpensEditor() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Create widget"].waitForExistence(timeout: 10))
        app.buttons["Create widget"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "My widget".count) + "UI test widget")
        app.buttons["Create widget"].tap()
        XCTAssertTrue(app.buttons["Run preview"].waitForExistence(timeout: 5) || app.navigationBars["UI test widget"].exists)
    }
    @MainActor func testSettingsAndGGUFImportAreDiscoverable() throws {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Local intelligence"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Import .gguf from Files"].exists)
    }
}
