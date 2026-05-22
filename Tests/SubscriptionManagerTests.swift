import XCTest
@testable import VeilCore

@MainActor
final class SubscriptionManagerTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-subscriptions-test-\(UUID().uuidString)")
        UserDefaults.standard.removeObject(forKey: "activeProfileId")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testGivenValidSubscriptionWhenAddedThenItPersistsWithOwnerOnlyPermissions() throws {
        let manager = SubscriptionManager(subscriptionsDir: tmpDir)

        let source = try manager.addSource(
            urlString: "https://subscriptions.example/list.txt",
            name: "Work"
        )

        let reloaded = SubscriptionManager(subscriptionsDir: tmpDir)
        XCTAssertEqual(reloaded.sources, [source])

        let attrs = try? FileManager.default.attributesOfItem(atPath: manager.subscriptionsFile.path)
        let perms = attrs?[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testGivenDuplicateSubscriptionURLWhenAddedThenItThrowsDuplicate() throws {
        let manager = SubscriptionManager(subscriptionsDir: tmpDir)
        _ = try manager.addSource(urlString: "https://subscriptions.example/list.txt", name: "Primary")

        XCTAssertThrowsError(
            try manager.addSource(urlString: "https://subscriptions.example/list.txt", name: "Copy")
        ) { error in
            XCTAssertEqual(error as? SubscriptionError, .duplicateURL)
        }
    }

    func testGivenSubscriptionRefreshWhenBodyContainsProfilesThenProfilesAreLabeledBySource() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/work",
            name: "Work"
        )

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000011@alpha.example:443?security=tls&type=tcp#Alpha
                trojan://secret@beta.example:443?security=tls&type=tcp#Beta
                """
            },
            measureLatency: { _ in nil }
        )

        XCTAssertEqual(summary.addedCount, 2)
        XCTAssertEqual(summary.skippedDuplicateCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(profiles.profiles.count, 2)
        XCTAssertEqual(profiles.profiles.map(\.sourceName), ["Work", "Work"])
        XCTAssertEqual(profiles.profiles.map(\.sourceId), [source.id, source.id])
        XCTAssertNotNil(subscriptions.sources.first?.lastRefreshedAt)
        XCTAssertNil(subscriptions.sources.first?.lastError)
    }

    func testGivenSubscriptionRefreshWhenLatencyIsMeasuredThenFastestProfileBecomesActive() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/fastest",
            name: "Fastest"
        )

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000021@slow.example:443?security=tls&type=tcp#Slow
                vless://00000000-0000-0000-0000-000000000022@fast.example:443?security=tls&type=tcp#Fast
                trojan://secret@down.example:443?security=tls&type=tcp#Down
                """
            },
            measureLatency: { profile in
                switch profile.server {
                case "slow.example": return 120
                case "fast.example": return 18
                default: return nil
                }
            }
        )

        XCTAssertEqual(summary.fastestProfileName, "Fast")
        XCTAssertEqual(profiles.activeProfile?.server, "fast.example")
    }

    func testGivenExistingManualDuplicateWhenSubscriptionRefreshesThenProfileIsAttachedToSource() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/duplicates",
            name: "Imported"
        )
        profiles.addProfile(ProxyConfig(
            proto: .vless,
            uuid: "00000000-0000-0000-0000-000000000041",
            server: "same.example",
            port: 443,
            name: "Existing",
            security: "tls"
        ))

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000041@same.example:443?security=tls&type=tcp#Same
                """
            },
            measureLatency: { _ in nil }
        )

        XCTAssertEqual(summary.addedCount, 0)
        XCTAssertEqual(summary.skippedDuplicateCount, 1)
        XCTAssertEqual(profiles.profiles.count, 1)
        XCTAssertEqual(profiles.profiles[0].sourceId, source.id)
        XCTAssertEqual(profiles.profiles[0].sourceName, "Imported")

        subscriptions.deleteSource(id: source.id, profileManager: profiles)
        XCTAssertTrue(profiles.profiles.isEmpty)
    }

    func testGivenSubscriptionProfilesWhenSelectingFastestThenActiveProfileChanges() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/select",
            name: "Select"
        )
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000051@slow.example:443?security=tls&type=tcp#Slow
                vless://00000000-0000-0000-0000-000000000052@fast.example:443?security=tls&type=tcp#Fast
                """
            },
            measureLatency: { _ in nil }
        )
        profiles.selectProfile(id: profiles.profiles.first { $0.server == "slow.example" }!.id)

        let selected = await subscriptions.selectFastestProfile(
            sourceId: source.id,
            profileManager: profiles,
            measureLatency: { profile in profile.server == "fast.example" ? 9 : 90 }
        )

        XCTAssertEqual(selected?.server, "fast.example")
        XCTAssertEqual(profiles.activeProfile?.server, "fast.example")
    }

    func testGivenSubscriptionDeletedThenProfilesFromThatSourceAreDeletedAndManualProfilesRemain() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/work",
            name: "Work"
        )
        profiles.addProfile(ProxyConfig(
            proto: .trojan,
            uuid: "manual-secret",
            server: "manual.example",
            port: 443,
            name: "Manual"
        ))
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000031@sub.example:443?security=tls&type=tcp#Sub
                """
            },
            measureLatency: { _ in nil }
        )
        let subscriptionProfileId = profiles.profiles.first { $0.sourceId == source.id }!.id
        profiles.selectProfile(id: subscriptionProfileId)

        subscriptions.deleteSource(id: source.id, profileManager: profiles)

        XCTAssertEqual(subscriptions.sources.count, 0)
        XCTAssertEqual(profiles.profiles.map(\.server), ["manual.example"])
        XCTAssertEqual(profiles.activeProfile?.server, "manual.example")
    }

    func testGivenLegacyProfilesWithOnlySourceNameWhenSubscriptionDeletedThenTheyAreRemoved() throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/legacy",
            name: "Legacy"
        )
        var legacy = ProxyConfig(
            proto: .vless,
            uuid: "00000000-0000-0000-0000-000000000061",
            server: "legacy.example",
            port: 443,
            name: "Legacy node",
            security: "tls"
        )
        legacy.sourceName = "Legacy"
        profiles.addProfile(legacy)
        profiles.addProfile(ProxyConfig(
            proto: .trojan,
            uuid: "manual-secret",
            server: "manual.example",
            port: 443,
            name: "Manual"
        ))

        subscriptions.deleteSource(id: source.id, profileManager: profiles)

        XCTAssertEqual(profiles.profiles.map(\.server), ["manual.example"])
    }

    func testGivenRefreshFailureWhenFetcherThrowsThenNoProfilesAreAddedAndErrorIsStored() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/down",
            name: "Down"
        )

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in throw SubscriptionFetchError.httpStatus(503) }
        )

        XCTAssertEqual(summary.addedCount, 0)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertTrue(profiles.profiles.isEmpty)
        XCTAssertTrue(subscriptions.sources.first?.lastError?.contains("503") == true)
    }
}
