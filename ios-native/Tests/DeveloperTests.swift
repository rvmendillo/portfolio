import XCTest
@testable import ReyPortfolioNative

final class DeveloperTests:XCTestCase {
    func testRealPythonFunctionsClassesImportsAndInput() async throws {
        let result=try await PythonRuntime.shared.run("from helpers import double\nclass Counter:\n    def values(self):\n        return [double(n) for n in range(4)]\nprint(Counter().values())\nprint(input())",files:["helpers.py":"def double(n):\n    return n*2\n"],input:"Rey\n")
        XCTAssertEqual(result.exitCode,0);XCTAssertEqual(result.output,"[0, 2, 4, 6]\nRey\n")
    }
    func testPythonErrorIsNotReportedAsSuccess() async throws {
        let result=try await PythonRuntime.shared.run("raise ValueError('expected failure')")
        XCTAssertEqual(result.exitCode,1);XCTAssertTrue(result.output.contains("expected failure"))
    }
    func testLoopLimit() async throws {
        let result=try await PythonRuntime.shared.run("while True:\n    pass")
        XCTAssertEqual(result.exitCode,1);XCTAssertTrue(result.output.contains("Execution limit"))
    }
    func testCompilerRejectsUnsupportedConstructs() async throws {
        do{_ = try await PythonRuntime.shared.compile("import socket\n",target:"java");XCTFail("Unsupported import silently accepted")}catch{XCTAssertTrue(error.localizedDescription.contains("Line 1"))}
    }
    @MainActor func testWorkspaceSurvivesReopening() throws {
        let workspace=IDEWorkspace();let name="test-\(UUID().uuidString).py";try workspace.add(name);workspace.text="print('persistent')"
        let reopened=IDEWorkspace();XCTAssertTrue(reopened.files.contains{$0.name==name && $0.text=="print('persistent')"});workspace.removeCurrent()
    }
    func testActualBundledModelInference() throws {
        let model=RYLocalModel();let path=try XCTUnwrap(Bundle.main.path(forResource:"rey-coder",ofType:"gguf",inDirectory:"Models"))
        try model.loadPath(path);defer{model.unload()}
        let result=try model.generate([["role":"system","content":"Answer concisely."],["role":"user","content":"What is 2 + 2? Reply with the number only."]],limit:16,token:{_ in})
        XCTAssertTrue(result.contains("4"),"Actual model response: \(result)")
    }
    func testLargeCalculatorValueDoesNotTrap() throws {XCTAssertFalse(MathFormatter.string(1e30).isEmpty);XCTAssertEqual(try SafeMath.evaluate("2 * -3 + 8"),2)}
}
