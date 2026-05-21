import XCTest
@testable import VeilCore

final class StatusSummaryTests: XCTestCase {
    func testGivenNoProfileOrDraftWhenDisconnectedThenConnectActionIsDisabled() {
        let summary = StatusSummary(
            state: .disconnected,
            displayConfig: nil,
            hasLaunchInput: false,
            pingMs: nil,
            packetsSent: 0,
            packetsRecv: 0,
            language: .en
        )

        XCTAssertEqual(summary.stateLabel, "Disconnected")
        XCTAssertEqual(summary.toggleTitle, "Connect")
        XCTAssertEqual(summary.toggleIcon, "play.fill")
        XCTAssertTrue(summary.isToggleDisabled)
        XCTAssertEqual(summary.profileMetric, "Not selected")
        XCTAssertEqual(summary.routeSummary, "Not set")
        XCTAssertEqual(summary.pingMetric, "—")
        XCTAssertEqual(summary.trafficMetric, "—")
        XCTAssertNil(summary.recoveryHint)
    }

    func testGivenDraftConfigWhenDisconnectedThenConnectActionIsEnabledAndRouteIsVisible() {
        let config = makeConfig(name: "", server: "edge.example", port: 443)

        let summary = StatusSummary(
            state: .disconnected,
            displayConfig: config,
            hasLaunchInput: true,
            pingMs: nil,
            packetsSent: 0,
            packetsRecv: 0,
            language: .ru
        )

        XCTAssertFalse(summary.isToggleDisabled)
        XCTAssertEqual(summary.toggleTitle, "Подключить")
        XCTAssertEqual(summary.profileMetric, "edge.example")
        XCTAssertEqual(summary.profileSummary, "edge.example")
        XCTAssertEqual(summary.routeSummary, "edge.example:443")
    }

    func testGivenConnectedVPNWhenStatsArriveThenMetricsShowLiveValues() {
        let config = makeConfig(name: "Work tunnel", server: "vpn.example", port: 8443)

        let summary = StatusSummary(
            state: .connected,
            displayConfig: config,
            hasLaunchInput: false,
            pingMs: 88,
            packetsSent: 12,
            packetsRecv: 34,
            language: .en
        )

        XCTAssertEqual(summary.stateLabel, "Connected")
        XCTAssertEqual(summary.toggleTitle, "Disconnect")
        XCTAssertEqual(summary.toggleIcon, "power")
        XCTAssertFalse(summary.isToggleDisabled)
        XCTAssertTrue(summary.isConnectionActivityActive)
        XCTAssertEqual(summary.pingMetric, "88 ms")
        XCTAssertEqual(summary.trafficMetric, "↑12  ↓34")
        XCTAssertEqual(summary.profileMetric, "Work tunnel")
    }

    func testGivenDisconnectingVPNThenToggleIsDisabledUntilCleanupFinishes() {
        let summary = StatusSummary(
            state: .disconnecting,
            displayConfig: makeConfig(name: "Mobile", server: "mobile.example", port: 443),
            hasLaunchInput: true,
            pingMs: 42,
            packetsSent: 1,
            packetsRecv: 2,
            language: .ru
        )

        XCTAssertEqual(summary.stateLabel, "Отключение…")
        XCTAssertEqual(summary.toggleTitle, "Отключение…")
        XCTAssertEqual(summary.toggleIcon, "power")
        XCTAssertTrue(summary.isToggleDisabled)
        XCTAssertTrue(summary.isConnectionActivityActive)
        XCTAssertEqual(summary.pingMetric, "—")
        XCTAssertEqual(summary.trafficMetric, "—")
        XCTAssertNil(summary.recoveryHint)
    }

    func testGivenSingBoxErrorThenRecoveryHintPointsToSettings() {
        let summary = StatusSummary(
            state: .error("sing-box not found"),
            displayConfig: nil,
            hasLaunchInput: true,
            pingMs: nil,
            packetsSent: 0,
            packetsRecv: 0,
            language: .en
        )

        XCTAssertEqual(summary.stateLabel, "sing-box not found")
        XCTAssertEqual(
            summary.recoveryHint,
            "Check the selected sing-box in Settings or download the bundled version again."
        )
    }

    func testGivenPortErrorThenRecoveryHintMentionsLocalPort() {
        let summary = StatusSummary(
            state: .error("sing-box did not open port 10808 within 5 sec"),
            displayConfig: nil,
            hasLaunchInput: true,
            pingMs: nil,
            packetsSent: 0,
            packetsRecv: 0,
            language: .en
        )

        XCTAssertTrue(summary.recoveryHint?.contains("127.0.0.1:10808") == true)
    }

    func testGivenGenericErrorThenRecoveryHintPointsToRedactedDiagnostics() {
        let summary = StatusSummary(
            state: .error("connection failed"),
            displayConfig: nil,
            hasLaunchInput: true,
            pingMs: nil,
            packetsSent: 0,
            packetsRecv: 0,
            language: .en
        )

        XCTAssertEqual(
            summary.recoveryHint,
            "Open the log and export diagnostics if you need help without sharing secrets."
        )
    }

    private func makeConfig(name: String, server: String, port: Int) -> ProxyConfig {
        ProxyConfig(
            proto: .vless,
            uuid: "00000000-0000-0000-0000-000000000000",
            server: server,
            port: port,
            name: name
        )
    }
}
