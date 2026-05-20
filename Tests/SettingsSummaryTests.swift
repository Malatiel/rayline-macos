import XCTest
@testable import VeilCore

final class SettingsSummaryTests: XCTestCase {
    func testGivenConnectedVPNWhenSummaryIsBuiltInEnglishThenSystemProxyReadsActive() {
        let summary = SettingsSummary(
            state: .connected,
            customSingBoxPath: "",
            language: .en
        )

        XCTAssertEqual(summary.socksEndpoint, "127.0.0.1:10808")
        XCTAssertEqual(summary.systemProxyStatus, "Active")
        XCTAssertTrue(summary.isSystemProxyActive)
        XCTAssertEqual(summary.singBoxDescription, "Uses bundled, downloaded, or system binary")
        XCTAssertEqual(summary.languageToggleTitle, "RU")
    }

    func testGivenDisconnectedVPNWhenSummaryIsBuiltInRussianThenSystemProxyReadsInactive() {
        let summary = SettingsSummary(
            state: .disconnected,
            customSingBoxPath: "",
            language: .ru
        )

        XCTAssertEqual(summary.systemProxyStatus, "Неактивен")
        XCTAssertFalse(summary.isSystemProxyActive)
        XCTAssertEqual(summary.singBoxDescription, "Используется встроенный, скачанный или системный бинарник")
        XCTAssertEqual(summary.languageToggleTitle, "EN")
    }

    func testGivenCustomSingBoxPathWhenSummaryIsBuiltThenItShowsTheExactPath() {
        let path = "/tmp/veil-test/sing-box"
        let summary = SettingsSummary(
            state: .error("network failed"),
            customSingBoxPath: path,
            language: .en
        )

        XCTAssertEqual(summary.singBoxDescription, path)
        XCTAssertEqual(summary.systemProxyStatus, "Inactive")
        XCTAssertFalse(summary.isSystemProxyActive)
    }
}
