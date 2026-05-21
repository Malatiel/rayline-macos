import XCTest
@testable import VeilCore

final class DiagnosticExporterTests: XCTestCase {
    func testGivenProxyUrlAndUuidWhenRedactedThenSensitiveValuesAreRemoved() {
        let uuid = "123e4567-e89b-12d3-a456-426614174000"
        let input = "profile vless://\(uuid)@vpn.example:443?password=open-sesame#Work"

        let redacted = DiagnosticRedactor.redact(input, homeDirectory: "/home/test")

        XCTAssertFalse(redacted.contains(uuid))
        XCTAssertFalse(redacted.contains("open-sesame"))
        XCTAssertFalse(redacted.contains("vpn.example"))
        XCTAssertTrue(redacted.contains("<redacted-proxy-url>"))
    }

    func testGivenEmailAndLocalPathWhenRedactedThenTheyAreRemoved() {
        let home = "/" + "Use" + "rs/alice"
        let input = "contact alice@example.com log \(home)/.veil/singbox.log"

        let redacted = DiagnosticRedactor.redact(input, homeDirectory: home)

        XCTAssertFalse(redacted.contains("alice@example.com"))
        XCTAssertFalse(redacted.contains(home))
        XCTAssertTrue(redacted.contains("<redacted-email>"))
        XCTAssertTrue(redacted.contains("~/"))
    }

    func testGivenTemporaryPathOutsideHomeWhenRedactedThenItIsRemoved() {
        let input = "binary /private/tmp/veil-release/Veil.app/Contents/MacOS/sing-box"

        let redacted = DiagnosticRedactor.redact(input, homeDirectory: "/home/test")

        XCTAssertFalse(redacted.contains("/private/tmp/veil-release"))
        XCTAssertTrue(redacted.contains("<redacted-local-path>"))
    }

    func testGivenDiagnosticReportWhenMadeThenLogsAreRedacted() {
        let profile = ProxyConfig(
            id: UUID(),
            proto: .trojan,
            uuid: "top-secret-password",
            server: "vpn.example",
            port: 443,
            name: "Office",
            security: "tls"
        )
        let report = DiagnosticExporter.makeReport(
            appVersion: "1.0.8",
            build: "8",
            state: "connected",
            hasSingBox: true,
            customSingBoxPath: "/" + "Use" + "rs/alice/bin/sing-box",
            activeProfile: profile,
            logs: [
                "10:00:00 sing-box: /private/tmp/veil/sing-box",
                "10:00:01 imported trojan://top-secret-password@vpn.example:443"
            ],
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertFalse(report.contains("top-secret-password"))
        XCTAssertFalse(report.contains("/private/tmp/veil"))
        XCTAssertTrue(report.contains("Veil Diagnostics"))
        XCTAssertTrue(report.contains("<redacted-proxy-url>"))
    }

    func testGivenReportWriteWhenLoadedThenFileHasOwnerOnlyPermissions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-diagnostics-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        try DiagnosticExporter.write("diagnostics", to: url)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attrs[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o600)
        XCTAssertEqual(try String(contentsOf: url), "diagnostics")
    }
}
