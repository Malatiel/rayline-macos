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

    func testGivenRemoteSubscriptionRemovesProfileWhenRefreshedThenStaleSourceProfileIsDeleted() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/stale",
            name: "Stale"
        )
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000071@keep.example:443?security=tls&type=tcp#Keep
                vless://00000000-0000-0000-0000-000000000072@drop.example:443?security=tls&type=tcp#Drop
                """
            },
            measureLatency: { _ in nil }
        )
        profiles.addProfile(ProxyConfig(
            proto: .trojan,
            uuid: "manual-secret",
            server: "manual.example",
            port: 443,
            name: "Manual"
        ))

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000071@keep.example:443?security=tls&type=tcp#Keep
                """
            },
            measureLatency: { _ in nil }
        )

        XCTAssertEqual(summary.addedCount, 0)
        XCTAssertEqual(summary.removedCount, 1)
        XCTAssertEqual(profiles.profiles.map(\.server).sorted(), ["keep.example", "manual.example"])
        XCTAssertNil(profiles.profiles.first { $0.server == "drop.example" })
    }

    func testGivenRemoteSubscriptionRenamesExistingConnectionWhenRefreshedThenProfileNameIsUpdated() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/rename",
            name: "Rename"
        )
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000081@same.example:443?security=tls&type=tcp#Old%20name
                """
            },
            measureLatency: { _ in nil }
        )
        let existingId = profiles.profiles[0].id

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000081@same.example:443?security=tls&type=tcp#New%20name
                """
            },
            measureLatency: { _ in nil }
        )

        XCTAssertEqual(profiles.profiles.count, 1)
        XCTAssertEqual(profiles.profiles[0].id, existingId)
        XCTAssertEqual(profiles.profiles[0].name, "New name")
        XCTAssertEqual(summary.updatedCount, 1)
    }

    func testGivenRefreshFailureWithExistingSourceProfilesThenReconciliationDoesNotDeleteThem() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/failure-keeps-local",
            name: "Failure"
        )
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000091@kept.example:443?security=tls&type=tcp#Kept
                """
            },
            measureLatency: { _ in nil }
        )

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in throw SubscriptionFetchError.httpStatus(503) },
            measureLatency: { _ in nil }
        )

        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(profiles.profiles.map(\.server), ["kept.example"])
    }

    func testGivenEmptySuccessfulSubscriptionWithExistingSourceProfilesThenRefreshFailsAndKeepsProfiles() async throws {
        let previousLanguage = LanguageManager.shared.language
        LanguageManager.shared.language = .en
        defer { LanguageManager.shared.language = previousLanguage }

        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/empty",
            name: "Empty"
        )
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000101@kept.example:443?security=tls&type=tcp#Kept
                """
            },
            measureLatency: { _ in nil }
        )

        let summary = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in "" },
            measureLatency: { _ in nil }
        )

        XCTAssertEqual(summary.addedCount, 0)
        XCTAssertEqual(summary.removedCount, 0)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(profiles.profiles.map(\.server), ["kept.example"])
        XCTAssertTrue(subscriptions.sources.first?.lastError?.contains("No valid profiles") == true)
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
        XCTAssertEqual(profiles.profiles.first { $0.server == "fast.example" }?.latencyMs, 9)
        XCTAssertEqual(profiles.profiles.first { $0.server == "slow.example" }?.latencyMs, 90)
    }

    func testGivenManySubscriptionProfilesWhenSelectingFastestThenLatencyChecksAreBoundedAndConcurrent() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/concurrent",
            name: "Concurrent"
        )
        for index in 0..<8 {
            var profile = ProxyConfig(
                proto: .vless,
                uuid: "00000000-0000-0000-0000-00000000020\(index)",
                server: "node-\(index).example",
                port: 443,
                name: "Node \(index)"
            )
            profile.sourceId = source.id
            profile.sourceName = source.name
            profiles.addProfile(profile)
        }
        let probe = LatencyProbe()

        let selected = await subscriptions.selectFastestProfile(
            sourceId: source.id,
            profileManager: profiles,
            maxConcurrentLatencyChecks: 3,
            measureLatency: { profile in
                await probe.started()
                try? await Task.sleep(nanoseconds: 20_000_000)
                await probe.finished()
                return profile.server == "node-6.example" ? 5 : 80
            }
        )

        let maxConcurrent = await probe.maxConcurrent()
        XCTAssertEqual(selected?.server, "node-6.example")
        XCTAssertGreaterThan(maxConcurrent, 1)
        XCTAssertLessThanOrEqual(maxConcurrent, 3)
        XCTAssertEqual(profiles.profiles.map(\.server), (0..<8).map { "node-\($0).example" })
        XCTAssertEqual(profiles.profiles.first { $0.server == "node-6.example" }?.latencyMs, 5)
    }

    func testGivenSubscriptionSyncUpdatesSameConnectionThenExistingLatencyIsPreserved() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/preserve-latency",
            name: "Preserve"
        )
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000401@same.example:443?security=tls&type=tcp#Old%20name
                """
            },
            measureLatency: { _ in 24 }
        )
        let existingId = profiles.profiles[0].id
        let latencyUpdatedAt = profiles.profiles[0].latencyUpdatedAt

        var updated = ProfileImportParser.parse(
            "vless://00000000-0000-0000-0000-000000000401@same.example:443?security=tls&type=tcp#New%20name"
        ).profiles
        updated[0].sourceId = source.id
        updated[0].sourceName = source.name
        profiles.syncSubscriptionProfiles(
            updated,
            sourceId: source.id,
            sourceName: source.name
        )

        XCTAssertEqual(profiles.profiles.count, 1)
        XCTAssertEqual(profiles.profiles[0].id, existingId)
        XCTAssertEqual(profiles.profiles[0].name, "New name")
        XCTAssertEqual(profiles.profiles[0].latencyMs, 24)
        XCTAssertEqual(profiles.profiles[0].latencyUpdatedAt, latencyUpdatedAt)
    }

    func testGivenRemoteSubscriptionReordersProfilesWhenRefreshedThenProviderOrderIsKept() async throws {
        let subscriptions = SubscriptionManager(subscriptionsDir: tmpDir)
        let profiles = ProfileManager(profilesDir: tmpDir.appendingPathComponent("profiles"))
        let source = try subscriptions.addSource(
            urlString: "https://subscriptions.example/reorder",
            name: "Reorder"
        )
        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000501@alpha.example:443?security=tls&type=tcp#Alpha
                vless://00000000-0000-0000-0000-000000000502@beta.example:443?security=tls&type=tcp#Beta
                """
            },
            measureLatency: { _ in nil }
        )

        _ = await subscriptions.refresh(
            sourceId: source.id,
            profileManager: profiles,
            fetch: { _ in
                """
                vless://00000000-0000-0000-0000-000000000502@beta.example:443?security=tls&type=tcp#Beta
                vless://00000000-0000-0000-0000-000000000501@alpha.example:443?security=tls&type=tcp#Alpha
                """
            },
            measureLatency: { profile in profile.server == "alpha.example" ? 1 : 100 }
        )

        XCTAssertEqual(profiles.profiles.map(\.server), ["beta.example", "alpha.example"])
        XCTAssertEqual(profiles.activeProfile?.server, "alpha.example")
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

private actor LatencyProbe {
    private var inFlight = 0
    private var peak = 0

    func started() {
        inFlight += 1
        peak = max(peak, inFlight)
    }

    func finished() {
        inFlight -= 1
    }

    func maxConcurrent() -> Int {
        peak
    }
}
