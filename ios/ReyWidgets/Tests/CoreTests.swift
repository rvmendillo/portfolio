import XCTest
import UIKit
@testable import ReyWidgets

final class CoreTests: XCTestCase {
    func testPointerEscapingArraysAndMissingValues() throws {
        let data = Data(#"{"a/b":{"~key":["₱500",null]},"ok":true,"n":12.5}"#.utf8)
        XCTAssertEqual(Bindings.value(at: "/a~1b/~0key/0", in: data), "₱500")
        XCTAssertNil(Bindings.value(at: "/a~1b/~0key/1", in: data))
        XCTAssertNil(Bindings.value(at: "/a~1b/~0key/-1", in: data))
        XCTAssertNil(Bindings.value(at: "ok", in: data))
        XCTAssertEqual(Bindings.value(at: "/ok", in: data), "true")
        XCTAssertEqual(Bindings.render("Value {{/n}} • {{/missing}}", data: data), "Value 12.5 • —")
    }
    func testUnicodeBindingRanges() {
        XCTAssertEqual(Bindings.render("👨‍💻 {{/x}} → {{/x}}", data: Data(#"{"x":"日本"}"#.utf8)), "👨‍💻 日本 → 日本")
    }
    func testRejectUnsafeAPIURLs() {
        for url in ["http://example.com", "file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.com/"] {
            var config = APIConfiguration(); config.url = url
            XCTAssertThrowsError(try config.validatedURL())
        }
        var valid = APIConfiguration(); valid.url = "https://example.com/api?q=1"
        XCTAssertNoThrow(try valid.validatedURL())
    }
    func testExportImportResetsIdentityAndNetwork() throws {
        var doc = WidgetDocument(); doc.name = "Private project"; doc.api.enabled = true
        doc.api.url = "https://example.com/api"; doc.api.credentialID = "PRIVATE-KEYCHAIN-ID"
        doc.snapshotRevision = UUID(); doc.publishedAt = Date()
        let data = try doc.exportData()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE-KEYCHAIN-ID"))
        let imported = try WidgetDocument.imported(data)
        XCTAssertNotEqual(imported.id, doc.id)
        XCTAssertFalse(imported.api.enabled)
        XCTAssertNil(imported.snapshotRevision)
        XCTAssertNil(imported.publishedAt)
    }
    func testInvalidSchemaAndOversizedPayloadsAreRejected() throws {
        var doc = WidgetDocument(); doc.schemaVersion = 2
        XCTAssertThrowsError(try doc.validate())
        doc.schemaVersion = 1; doc.native.accent = "red"
        XCTAssertThrowsError(try doc.validate())
        doc.native.accent = "#123456"; doc.html = String(repeating: "a", count: 200_001)
        XCTAssertThrowsError(try doc.validate())
        XCTAssertThrowsError(try WidgetDocument.imported(Data(repeating: 0, count: 1_500_001)))
    }
    func testCacheIsInvalidatedWhenRequestChangesAndFailedWritePreservesDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SharedStore(root: root)
        var doc = WidgetDocument(); try store.save(doc)
        let cache = APICache(signature: doc.api.signature, json: Data("{}".utf8), fetchedAt: Date())
        try store.saveCache(cache, id: doc.id)
        XCTAssertNotNil(store.cache(doc))
        doc.api.url = "https://example.com/new"
        XCTAssertNil(store.cache(doc))
        doc.name = ""
        XCTAssertThrowsError(try store.save(doc))
        XCTAssertEqual(try store.load(doc.id).name, "Untitled widget")
    }
    func testAllTemplatesValidateAndRoundTrip() throws {
        XCTAssertEqual(Templates.all.count, 6)
        for doc in Templates.all {
            try doc.validate()
            XCTAssertEqual(try JSONDecoder().decode(WidgetDocument.self, from: JSONEncoder().encode(doc)), doc)
        }
    }
    func testAIRejectsMissingFieldsAndTruncatedOutput() throws {
        let fenced = "```json\n{\"html\":\"<p>Hello</p>\",\"css\":\"p{color:red}\",\"javascript\":\"\"}\n```"
        XCTAssertEqual(try GeneratedWidget.parse(fenced).html, "<p>Hello</p>")
        XCTAssertThrowsError(try GeneratedWidget.parse("{\"html\":\"Hi\"}"))
        XCTAssertThrowsError(try GeneratedWidget.parse("{\"html\":\"Hi"))
    }
    func testHTMLDataCannotBreakScriptBoundary() throws {
        let doc = WidgetDocument()
        let malicious = Data(#"{"x":"</script><script>fetch('https://evil.test')</script>","y":"日本"}"#.utf8)
        let page = HTMLRuntime.page(doc, data: malicious, size: .small)
        XCTAssertFalse(page.contains("fetch('https://evil.test')"))
        XCTAssertTrue(page.contains("connect-src 'none'"))
        XCTAssertTrue(page.contains("form-action 'none'"))
        XCTAssertTrue(page.contains(malicious.base64EncodedString()))
    }
    @MainActor func testHTMLSnapshotWaitsForJavaScriptAndCapturesAllSizes() async throws {
        // Run in the app's hosted test process, using the same WebKit compositor
        // and publishing path as the editor. No model or external network needed.
        for _ in 0..<100 {
            if UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        var doc = WidgetDocument(); doc.mode = .html
        doc.html = "<div data-bind=\"/title\"></div>"
        doc.css = "body{background:#FF0000}div{position:absolute;top:8px;left:8px}"
        doc.javascript = """
        widget.ready = new Promise(resolve => setTimeout(() => {
            document.body.style.background = widget.get('/color');
            resolve();
        }, 80));
        """
        let payload = Data(##"{"title":"Ready","color":"#29C7FF"}"##.utf8)
        for size in WidgetSize.allCases {
            let png = try await SnapshotRenderer().render(page: HTMLRuntime.page(doc, data: payload, size: size), size: size)
            let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
            XCTAssertGreaterThanOrEqual(image.width, Int(size.width))
            XCTAssertEqual(Double(image.width) / Double(image.height), Double(size.width / size.height), accuracy: 0.01)
            // Read the center pixel in an explicit RGBA color space. Red would
            // mean capture happened before widget.ready or JavaScript failed.
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.translateBy(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2))
                context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            }
            for (actual, expected) in zip(rgba, [41, 199, 255, 255]) {
                XCTAssertLessThanOrEqual(abs(Int(actual) - expected), 2, "Wrong rendered color for \(size.rawValue)")
            }
        }
    }
}
