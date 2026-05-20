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
