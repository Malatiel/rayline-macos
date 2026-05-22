import XCTest
@testable import RaylineCore

@MainActor
final class ProfileManagerTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayline-test-\(UUID().uuidString)")
        UserDefaults.standard.removeObject(forKey: "activeProfileId")
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func makeManager() -> ProfileManager {
        ProfileManager(profilesDir: tmpDir)
    }

    private func sampleConfig(name: String = "Test") -> ProxyConfig {
        ProxyConfig(proto: .vless, uuid: "test-uuid", server: "1.2.3.4", port: 443, name: name)
    }

    // MARK: - Add / Delete / Rename

    func testAddProfile() {
        let mgr = makeManager()
        XCTAssertTrue(mgr.profiles.isEmpty)

        mgr.addProfile(sampleConfig())
        XCTAssertEqual(mgr.profiles.count, 1)
        XCTAssertEqual(mgr.profiles.first?.name, "Test")
        XCTAssertNotNil(mgr.activeProfileId, "First profile should become active")
    }

    func testAddMultipleProfiles() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig(name: "A"))
        mgr.addProfile(sampleConfig(name: "B"))
        XCTAssertEqual(mgr.profiles.count, 2)
        XCTAssertEqual(mgr.profiles[0].name, "A")
        XCTAssertEqual(mgr.profiles[1].name, "B")
    }

    func testDeleteProfile() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig())
        let id = mgr.profiles.first!.id
        mgr.deleteProfile(id: id)
        XCTAssertTrue(mgr.profiles.isEmpty)
        XCTAssertNil(mgr.activeProfileId)
    }

    func testDeleteActiveProfileSwitchesToNext() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig(name: "A"))
        mgr.addProfile(sampleConfig(name: "B"))
        let idA = mgr.profiles[0].id
        let idB = mgr.profiles[1].id
        mgr.selectProfile(id: idA)

        mgr.deleteProfile(id: idA)
        XCTAssertEqual(mgr.activeProfileId, idB)
    }

    func testRenameProfile() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig(name: "Old"))
        let id = mgr.profiles.first!.id
        mgr.renameProfile(id: id, name: "New")
        XCTAssertEqual(mgr.profiles.first?.name, "New")
    }

    func testRenameNonExistentProfileNoOp() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig(name: "Keep"))
        mgr.renameProfile(id: UUID(), name: "Changed")
        XCTAssertEqual(mgr.profiles.first?.name, "Keep")
    }

    // MARK: - Select

    func testSelectProfile() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig(name: "A"))
        mgr.addProfile(sampleConfig(name: "B"))
        let idB = mgr.profiles[1].id
        mgr.selectProfile(id: idB)
        XCTAssertEqual(mgr.activeProfileId, idB)
    }

    func testSelectNonExistentProfileNoOp() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig())
        let original = mgr.activeProfileId
        mgr.selectProfile(id: UUID())
        XCTAssertEqual(mgr.activeProfileId, original)
    }

    func testActiveProfile() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig(name: "X"))
        XCTAssertEqual(mgr.activeProfile?.name, "X")
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let mgr1 = makeManager()
        mgr1.addProfile(sampleConfig(name: "Persist"))

        // Load fresh from same directory
        let mgr2 = makeManager()
        XCTAssertEqual(mgr2.profiles.count, 1)
        XCTAssertEqual(mgr2.profiles.first?.name, "Persist")
    }

    func testLatencyRoundTripAndTimeoutState() {
        let mgr1 = makeManager()
        mgr1.addProfile(sampleConfig(name: "Fast"))
        mgr1.addProfile(sampleConfig(name: "Timeout"))
        let fastId = mgr1.profiles[0].id
        let timeoutId = mgr1.profiles[1].id
        let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)

        mgr1.updateLatencyMeasurements([
            ProfileLatencyMeasurement(profileId: fastId, latencyMs: 18, measuredAt: measuredAt),
            ProfileLatencyMeasurement(profileId: timeoutId, latencyMs: nil, measuredAt: measuredAt)
        ])

        let mgr2 = makeManager()
        XCTAssertEqual(mgr2.profiles[0].latencyMs, 18)
        XCTAssertEqual(mgr2.profiles[0].latencyUpdatedAt, measuredAt)
        XCTAssertNil(mgr2.profiles[1].latencyMs)
        XCTAssertEqual(mgr2.profiles[1].latencyUpdatedAt, measuredAt)
    }

    func testLoadLegacyProfileWithoutLatencyFields() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let legacyJSON = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000301",
            "proto": "vless",
            "uuid": "legacy-uuid",
            "server": "legacy.example",
            "port": 443,
            "name": "Legacy",
            "security": "tls",
            "network": "tcp",
            "sni": "",
            "host": "",
            "path": "/",
            "fp": "",
            "pbk": "",
            "shortId": "",
            "encryption": "none",
            "method": "",
            "allowInsecure": false
          }
        ]
        """
        try legacyJSON.write(to: tmpDir.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)

        let mgr = makeManager()

        XCTAssertEqual(mgr.profiles.count, 1)
        XCTAssertEqual(mgr.profiles[0].server, "legacy.example")
        XCTAssertNil(mgr.profiles[0].latencyMs)
        XCTAssertNil(mgr.profiles[0].latencyUpdatedAt)
        XCTAssertNil(mgr.lastError)
    }

    func testFilePermissions() {
        let mgr = makeManager()
        mgr.addProfile(sampleConfig())

        let attrs = try? FileManager.default.attributesOfItem(atPath: mgr.profilesFile.path)
        let perms = attrs?[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600, "Profiles file should have 0600 permissions")
    }

    func testLoadCorruptedFileReportsError() {
        // Write garbage to profiles.json
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent("profiles.json")
        try? "not valid json".write(to: file, atomically: true, encoding: .utf8)

        let mgr = makeManager()
        XCTAssertTrue(mgr.profiles.isEmpty)
        XCTAssertNotNil(mgr.lastError, "Corrupted file should set lastError")
    }

    func testSaveToReadOnlyDirReportsError() {
        // Create a read-only directory
        let readOnlyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayline-readonly-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnlyDir.path)

        let mgr = ProfileManager(profilesDir: readOnlyDir.appendingPathComponent("sub"))
        mgr.addProfile(sampleConfig())
        XCTAssertNotNil(mgr.lastError, "Save to read-only dir should set lastError")

        // Cleanup
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
        try? FileManager.default.removeItem(at: readOnlyDir)
    }

    func testSuccessfulSaveClearsError() {
        // First force an error
        let mgr = makeManager()

        // Write garbage, load to set error
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try? "bad".write(to: mgr.profilesFile, atomically: true, encoding: .utf8)

        let mgr2 = makeManager()
        XCTAssertNotNil(mgr2.lastError)

        // Now add a valid profile — should clear error
        mgr2.addProfile(sampleConfig())
        XCTAssertNil(mgr2.lastError)
    }

    // MARK: - Duplicate ID

    func testAddDuplicateIdGetsNewId() {
        let mgr = makeManager()
        var cfg = sampleConfig(name: "Original")
        mgr.addProfile(cfg)

        cfg.name = "Duplicate"
        mgr.addProfile(cfg)

        XCTAssertEqual(mgr.profiles.count, 2)
        XCTAssertNotEqual(mgr.profiles[0].id, mgr.profiles[1].id)
    }

    // MARK: - Empty state

    func testNoFileOnDisk() {
        let mgr = makeManager()
        XCTAssertTrue(mgr.profiles.isEmpty)
        XCTAssertNil(mgr.lastError)
    }
}
