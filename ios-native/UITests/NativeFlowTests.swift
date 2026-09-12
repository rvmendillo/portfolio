import XCTest

final class NativeFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["app-about"].waitForExistence(timeout: 15))
    }

    private func wait(_ element: XCUIElement, _ predicate: NSPredicate, timeout: TimeInterval = 15) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func openApp(_ name: String) {
        let tile = app.buttons["app-" + name]
        for _ in 0..<4 {
            if tile.isHittable { break }
            app.scrollViews["desktop-apps"].swipeUp()
        }
        wait(tile, NSPredicate(format: "hittable == true"))
        tile.tap()
        XCTAssertTrue(app.buttons["app-close"].waitForExistence(timeout: 10))
    }

    private func createFile(_ source: String) -> String {
        let name = "u" + UUID().uuidString.prefix(3).lowercased() + ".py"
        app.buttons["New file"].tap()
        let alert = app.alerts["New file"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap()
        alert.textFields.firstMatch.typeText(name)
        alert.buttons["Create"].tap()
        let editor = app.textViews["code-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(source)
        return name
    }

    private func assertOutput(_ text: String) {
        let output = app.descendants(matching: .any).matching(identifier: "program-output").firstMatch
        wait(output, NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text), timeout: 30)
        wait(output, NSPredicate(format: "label CONTAINS 'Exit code: 0' OR value CONTAINS 'Exit code: 0'"))
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAllNativeAppsOpenAndClose() {
        screenshot("Native desktop")
        for name in ["about", "resume", "projects", "files", "browser", "terminal", "ide", "designer", "transpiler", "assistant", "studio", "settings", "calculator"] {
            openApp(name)
            app.buttons["app-close"].tap()
            XCTAssertTrue(app.buttons["app-about"].waitForExistence(timeout: 10))
        }
    }

    func testIDEEditsRunsAndPersistsAfterRelaunch() {
        openApp("ide")
        let name = createFile("def square(n):\n    return n * n\n\nprint(square(7))\n")
        app.buttons["ide-run"].tap()
        assertOutput("49")
        screenshot("Native IDE Python output")
        app.buttons["app-close"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["app-about"].waitForExistence(timeout: 15))
        openApp("ide")
        app.buttons["ide-files"].tap()
        app.buttons.matching(identifier: name).firstMatch.tap()
        XCTAssertTrue((app.textViews["code-editor"].value as? String ?? "").contains("def square(n):"))
        app.buttons["ide-run"].tap()
        assertOutput("49")
    }

    func testLocalAIGeneratesReviewedExecutableCodeAndStops() {
        openApp("ide")
        _ = createFile("print(\"before AI edit\")\n")
        app.buttons["ide-ai"].tap()
        app.buttons["ai-load"].tap()
        let status = app.staticTexts["ai-model-status"]
        wait(status, NSPredicate(format: "label CONTAINS 'ready on this device'"), timeout: 120)
        let prompt = app.descendants(matching: .any).matching(identifier: "ai-prompt").firstMatch
        prompt.tap()
        prompt.typeText("Replace the current Python file. Define square(n) returning n * n, then print(square(7)). Return only the complete file in a python code block.")
        app.buttons["ai-send"].tap()
        XCTAssertTrue(app.buttons["ai-review"].waitForExistence(timeout: 180))
        app.buttons["ai-review"].tap()
        XCTAssertTrue(app.buttons["ai-apply"].waitForExistence(timeout: 10))
        screenshot("Native local AI edit review")
        app.buttons["ai-apply"].tap()
        app.buttons["New conversation"].tap()
        prompt.tap()
        prompt.typeText("Write every integer from 1 to 10000, one per line.")
        app.buttons["ai-send"].tap()
        wait(app.buttons["ai-stop"], NSPredicate(format: "enabled == true"))
        app.buttons["ai-stop"].tap()
        wait(app.buttons["ai-unload"], NSPredicate(format: "enabled == true"), timeout: 30)
        app.buttons["ai-unload"].tap()
        wait(status, NSPredicate(format: "label CONTAINS 'Model unloaded'"))
        app.buttons["ai-close"].tap()
        app.buttons["ide-run"].tap()
        assertOutput("49")
        screenshot("Native IDE runs local AI code")
    }
}
