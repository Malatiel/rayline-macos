import XCTest
@testable import VeilCore

final class ProfilesSummaryTests: XCTestCase {
    func testGivenNoProfilesWhenImportIsCollapsedThenEmptyStateIsVisibleAndPanelStaysHidden() {
        let summary = ProfilesSummary(
            profiles: [],
            activeProfileId: nil,
            isImportExpanded: false,
            importText: "",
            vpnState: .disconnected,
            language: .en
        )

        XCTAssertTrue(summary.isEmpty)
        XCTAssertFalse(summary.shouldShowImportPanel)
        XCTAssertEqual(summary.importButtonTitle, "Import")
        XCTAssertEqual(summary.importButtonIcon, "plus.circle")
        XCTAssertEqual(summary.emptyTitle, "No profile yet")
        XCTAssertTrue(summary.rows.isEmpty)
    }

    func testGivenDraftTextWhenImportIsCollapsedThenPanelRemainsVisible() {
        let summary = ProfilesSummary(
            profiles: [makeConfig(name: "Office", server: "office.example", port: 443)],
            activeProfileId: nil,
            isImportExpanded: false,
            importText: " vless://draft ",
            vpnState: .disconnected,
            language: .ru
        )

        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.shouldShowImportPanel)
        XCTAssertEqual(summary.importButtonTitle, "Импорт")
        XCTAssertEqual(summary.importButtonIcon, "plus.circle")
    }

    func testGivenActiveProfileWhileConnectedThenDeleteIsLockedForOnlyThatRow() {
        let active = makeConfig(name: "Active", server: "active.example", port: 443)
        let inactive = makeConfig(name: "Backup", server: "backup.example", port: 8443)

        let summary = ProfilesSummary(
            profiles: [active, inactive],
            activeProfileId: active.id,
            isImportExpanded: true,
            importText: "",
            vpnState: .connected,
            language: .en
        )

        XCTAssertEqual(summary.importButtonTitle, "Hide import")
        XCTAssertEqual(summary.importButtonIcon, "chevron.up")
        XCTAssertEqual(summary.rows.count, 2)
        XCTAssertTrue(summary.rows[0].isActive)
        XCTAssertTrue(summary.rows[0].isDeleteDisabled)
        XCTAssertFalse(summary.rows[1].isActive)
        XCTAssertFalse(summary.rows[1].isDeleteDisabled)
        XCTAssertEqual(summary.rows[0].activeBadge, "active")
    }

    func testGivenUnnamedProfileThenServerIsUsedAsDisplayName() {
        let config = makeConfig(name: "", server: "fallback.example", port: 9443)

        let summary = ProfilesSummary(
            profiles: [config],
            activeProfileId: nil,
            isImportExpanded: false,
            importText: "",
            vpnState: .disconnecting,
            language: .ru
        )

        XCTAssertEqual(summary.rows[0].displayName, "fallback.example")
        XCTAssertEqual(summary.rows[0].route, "fallback.example:9443")
        XCTAssertEqual(summary.rows[0].protocolName, "VLESS")
        XCTAssertFalse(summary.rows[0].isDeleteDisabled)
    }

    func testGivenSubscriptionProfileThenSourceLabelIsExposed() {
        var config = makeConfig(name: "Edge", server: "edge.example", port: 443)
        config.sourceName = "Work"

        let summary = ProfilesSummary(
            profiles: [config],
            activeProfileId: nil,
            isImportExpanded: false,
            importText: "",
            vpnState: .disconnected,
            language: .en
        )

        XCTAssertEqual(summary.rows[0].sourceLabel, "Work")
    }

    func testGivenSubscriptionSourceWithLastSummaryThenDisplaySummaryShowsCountsAndRefreshStatus() {
        var source = SubscriptionSource(
            name: "Work",
            url: "https://subscriptions.example/work",
            lastRefreshedAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastSummary: "Added: 0, duplicates: 2, updated: 1, removed: 1, failed: 0"
        )
        source.lastError = nil

        let summary = SubscriptionSourceDisplaySummary(
            source: source,
            profileCount: 3,
            language: .en
        )

        XCTAssertEqual(summary.statusIcon, "checkmark.circle")
        XCTAssertFalse(summary.isError)
        XCTAssertEqual(summary.profileCountText, "3 profiles")
        XCTAssertTrue(summary.detail.contains("3 profiles"))
        XCTAssertTrue(summary.detail.contains("updated: 1"))
        XCTAssertTrue(summary.detail.contains("removed: 1"))
        XCTAssertTrue(summary.detail.contains("Last refresh"))
    }

    func testGivenSubscriptionSourceWithErrorThenDisplaySummaryPrioritizesFailure() {
        var source = SubscriptionSource(
            name: "Work",
            url: "https://subscriptions.example/work",
            lastRefreshedAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastSummary: "Added: 1, duplicates: 0, updated: 0, removed: 0, failed: 0"
        )
        source.lastError = "No valid profiles found in subscription"

        let summary = SubscriptionSourceDisplaySummary(
            source: source,
            profileCount: 1,
            language: .en
        )

        XCTAssertEqual(summary.statusIcon, "exclamationmark.triangle")
        XCTAssertTrue(summary.isError)
        XCTAssertEqual(summary.profileCountText, "1 profile")
        XCTAssertTrue(summary.detail.contains("Refresh failed"))
        XCTAssertTrue(summary.detail.contains("No valid profiles"))
        XCTAssertFalse(summary.detail.contains("Added: 1"))
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
