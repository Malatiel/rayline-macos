import XCTest
@testable import VeilCore

final class SharedCasesTests: XCTestCase {

    func testSharedParserCases() throws {
        let url = Bundle.module.url(forResource: "shared_test_cases", withExtension: "json")
        XCTAssertNotNil(url)
        let data = try Data(contentsOf: XCTUnwrap(url))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(root["parse_tests"] as? [[String: Any]])

        for testCase in cases {
            let name = try XCTUnwrap(testCase["name"] as? String)
            let uri = try XCTUnwrap(testCase["uri"] as? String)
            let expect = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let expectValid = try XCTUnwrap(expect["valid"] as? Bool)

            let parsed: ProxyConfig?
            do {
                parsed = try ProxyParser.parse(uri)
            } catch {
                parsed = nil
            }

            XCTAssertEqual(parsed?.isValid ?? false, expectValid, "\(name): valid mismatch")
            guard expectValid, let cfg = parsed else { continue }

            assertString(expect, "protocol", cfg.proto.rawValue, name)
            assertString(expect, "server", cfg.server, name)
            assertInt(expect, "port", cfg.port, name)
            assertString(expect, "uuid", cfg.uuid, name)
            assertString(expect, "security", cfg.security, name)
            assertString(expect, "network", cfg.network, name)
            assertString(expect, "sni", cfg.sni, name)
            assertString(expect, "host", cfg.host, name)
            assertString(expect, "path", cfg.path, name)
            assertString(expect, "name", cfg.name, name)
            assertString(expect, "method", cfg.method, name)
            assertString(expect, "pbk", cfg.pbk, name)
            assertString(expect, "short_id", cfg.shortId, name)
            assertString(expect, "fp", cfg.fp, name)
            assertBool(expect, "allow_insecure", cfg.allowInsecure, name)
        }
    }

    private func assertString(_ expect: [String: Any], _ key: String, _ actual: String, _ name: String) {
        guard let expected = expect[key] as? String else { return }
        XCTAssertEqual(actual, expected, "\(name): \(key) mismatch")
    }

    private func assertInt(_ expect: [String: Any], _ key: String, _ actual: Int, _ name: String) {
        guard let expected = expect[key] as? Int else { return }
        XCTAssertEqual(actual, expected, "\(name): \(key) mismatch")
    }

    private func assertBool(_ expect: [String: Any], _ key: String, _ actual: Bool, _ name: String) {
        guard let expected = expect[key] as? Bool else { return }
        XCTAssertEqual(actual, expected, "\(name): \(key) mismatch")
    }
}
