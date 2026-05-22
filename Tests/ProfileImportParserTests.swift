import XCTest
@testable import VeilCore

@MainActor
final class ProfileImportParserTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-import-test-\(UUID().uuidString)")
        UserDefaults.standard.removeObject(forKey: "activeProfileId")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testGivenMixedBulkTextWhenParsedThenValidProfilesAreReturnedAndBrokenLinksAreReported() {
        let text = """
        notes before import
        vless://00000000-0000-0000-0000-000000000001@alpha.example:443?security=tls&type=tcp#Alpha
        vless://missing-port@example.com?security=tls&type=tcp#Broken
        ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@beta.example:8388#Beta
        """

        let result = ProfileImportParser.parse(text)

        XCTAssertEqual(result.profiles.count, 2)
        XCTAssertEqual(result.profiles.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].input.contains("missing-port"))
    }

    func testGivenBase64SubscriptionBodyWhenParsedThenProfilesAreDecoded() {
        let subscription = """
        trojan://secret@gamma.example:443?security=tls&type=tcp#Gamma
        vless://00000000-0000-0000-0000-000000000002@delta.example:8443?security=reality&type=tcp&pbk=pub&sid=01#Delta
        """
        let encoded = Data(subscription.utf8).base64EncodedString()

        let result = ProfileImportParser.parse(encoded)

        XCTAssertEqual(result.profiles.count, 2)
        XCTAssertEqual(result.profiles[0].proto, .trojan)
        XCTAssertEqual(result.profiles[1].security, "reality")
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testGivenHugeImportTextWhenParsedThenItIsRejectedWithoutScanningSecrets() {
        let huge = String(repeating: "vless://00000000-0000-0000-0000-000000000003@huge.example:443?security=tls&type=tcp#Huge\n", count: 30_000)

        let result = ProfileImportParser.parse(huge)

        XCTAssertTrue(result.profiles.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures[0].message, "Import text is too large")
    }

    func testGivenBulkProfilesWhenAddedThenExistingAndInBatchDuplicatesAreSkipped() {
        let manager = ProfileManager(profilesDir: tmpDir)
        let existing = ProxyConfig(
            proto: .vless,
            uuid: "00000000-0000-0000-0000-000000000004",
            server: "same.example",
            port: 443,
            name: "Existing",
            security: "tls"
        )
        manager.addProfile(existing)

        var renamedDuplicate = existing
        renamedDuplicate.id = UUID()
        renamedDuplicate.name = "Renamed duplicate"
        let newProfile = ProxyConfig(
            proto: .trojan,
            uuid: "secret",
            server: "new.example",
            port: 443,
            name: "New",
            security: "tls"
        )

        let result = manager.addProfiles([renamedDuplicate, newProfile, newProfile])

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.skippedDuplicateCount, 2)
        XCTAssertEqual(manager.profiles.count, 2)
        XCTAssertEqual(manager.profiles[1].name, "New")
        XCTAssertEqual(manager.activeProfileId, existing.id)
    }
}
