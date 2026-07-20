import XCTest
@testable import RaylineCore

@MainActor
final class VPNManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: VPNManager.customSingBoxPathKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: VPNManager.customSingBoxPathKey)
        super.tearDown()
    }

    // MARK: - stripAnsi

    func testStripAnsiPlainText() {
        XCTAssertEqual(VPNManager.stripAnsi("hello world"), "hello world")
    }

    func testStripAnsiColourCodes() {
        XCTAssertEqual(VPNManager.stripAnsi("\u{1B}[32mOK\u{1B}[0m"), "OK")
    }

    func testStripAnsiMultipleCodes() {
        let input = "\u{1B}[1;31mERROR\u{1B}[0m: \u{1B}[33msomething\u{1B}[0m"
        XCTAssertEqual(VPNManager.stripAnsi(input), "ERROR: something")
    }

    func testStripAnsiEmptyString() {
        XCTAssertEqual(VPNManager.stripAnsi(""), "")
    }

    func testStripAnsiNoEscapeButBrackets() {
        XCTAssertEqual(VPNManager.stripAnsi("[info] started"), "[info] started")
    }

    func testStripAnsiPartialEscape() {
        // ESC without [ should be kept (edge case — stripAnsi only strips ESC[ sequences)
        XCTAssertEqual(VPNManager.stripAnsi("\u{1B}not-bracket"), "\u{1B}not-bracket")
    }

    // MARK: - Logging

    func testAddLog() {
        let vpn = VPNManager(performStartupRecovery: false)
        let before = vpn.logs.count
        vpn.addLog("test message")
        XCTAssertEqual(vpn.logs.count, before + 1)
        XCTAssertTrue(vpn.logs.last!.contains("test message"))
    }

    func testAddLogTimestamp() {
        let vpn = VPNManager(performStartupRecovery: false)
        vpn.addLog("hello")
        // Should contain HH:mm:ss prefix
        let log = vpn.logs[0]
        let parts = log.split(separator: " ", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains(":"), "First part should be a timestamp")
    }

    func testLogCapAt300() {
        let vpn = VPNManager(performStartupRecovery: false)
        for i in 0..<350 {
            vpn.addLog("line \(i)")
        }
        XCTAssertEqual(vpn.logs.count, 300)
        XCTAssertTrue(vpn.logs.first!.contains("line 50"), "Oldest 50 entries should be evicted")
        XCTAssertTrue(vpn.logs.last!.contains("line 349"))
    }

    func testClearLog() {
        let vpn = VPNManager(performStartupRecovery: false)
        vpn.addLog("a")
        vpn.addLog("b")
        vpn.clearLog()
        XCTAssertTrue(vpn.logs.isEmpty)
    }

    // MARK: - Initial state

    func testInitialState() {
        let vpn = VPNManager(performStartupRecovery: false)
        XCTAssertFalse(vpn.state.isConnected)
        XCTAssertFalse(vpn.state.isConnecting)
        XCTAssertNil(vpn.config)
        XCTAssertNil(vpn.pingMs)
        XCTAssertEqual(vpn.packetsSent, 0)
        XCTAssertEqual(vpn.packetsRecv, 0)
    }

    // MARK: - Local sing-box selection

    func testSetCustomSingBoxPathAcceptsExecutableFile() throws {
        let path = try makeTempSingBox(permissions: 0o755)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let vpn = VPNManager(performStartupRecovery: false)
        XCTAssertTrue(vpn.setCustomSingBoxPath(path))
        XCTAssertEqual(vpn.customSingBoxPath, path)
        XCTAssertEqual(UserDefaults.standard.string(forKey: VPNManager.customSingBoxPathKey), path)
        XCTAssertEqual(vpn.findSingBox(), path)
        XCTAssertTrue(vpn.hasSingBox)
    }

    func testSetCustomSingBoxPathRejectsMissingFile() {
        let path = NSTemporaryDirectory() + "missing-sing-box-\(UUID().uuidString)"

        let vpn = VPNManager(performStartupRecovery: false)
        XCTAssertFalse(vpn.setCustomSingBoxPath(path))
        XCTAssertTrue(vpn.customSingBoxPath.isEmpty)
        XCTAssertNil(UserDefaults.standard.string(forKey: VPNManager.customSingBoxPathKey))
        XCTAssertTrue(vpn.state.isError)
    }

    func testSetCustomSingBoxPathRejectsNonExecutableFile() throws {
        let path = try makeTempSingBox(permissions: 0o644)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let vpn = VPNManager(performStartupRecovery: false)
        XCTAssertFalse(vpn.setCustomSingBoxPath(path))
        XCTAssertTrue(vpn.customSingBoxPath.isEmpty)
        XCTAssertNil(UserDefaults.standard.string(forKey: VPNManager.customSingBoxPathKey))
        XCTAssertTrue(vpn.state.isError)
    }

    func testClearCustomSingBoxPathRemovesSavedPath() throws {
        let path = try makeTempSingBox(permissions: 0o755)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let vpn = VPNManager(performStartupRecovery: false)
        XCTAssertTrue(vpn.setCustomSingBoxPath(path))

        vpn.clearCustomSingBoxPath()
        XCTAssertTrue(vpn.customSingBoxPath.isEmpty)
        XCTAssertNil(UserDefaults.standard.string(forKey: VPNManager.customSingBoxPathKey))
    }

    func testStateEquatable() {
        XCTAssertEqual(VPNManager.State.disconnected, VPNManager.State.disconnected)
        XCTAssertEqual(VPNManager.State.connected, VPNManager.State.connected)
        XCTAssertEqual(VPNManager.State.error("x"), VPNManager.State.error("x"))
        XCTAssertNotEqual(VPNManager.State.error("x"), VPNManager.State.error("y"))
        XCTAssertNotEqual(VPNManager.State.connected, VPNManager.State.disconnected)
    }

    func testStateFlags() {
        XCTAssertTrue(VPNManager.State.connected.isConnected)
        XCTAssertFalse(VPNManager.State.connected.isConnecting)
        XCTAssertFalse(VPNManager.State.connected.isError)

        XCTAssertTrue(VPNManager.State.connecting.isConnecting)
        XCTAssertFalse(VPNManager.State.connecting.isConnected)

        XCTAssertTrue(VPNManager.State.disconnecting.isDisconnecting)
        XCTAssertFalse(VPNManager.State.disconnecting.isConnecting)
        XCTAssertFalse(VPNManager.State.disconnecting.isConnected)
        XCTAssertFalse(VPNManager.State.disconnecting.isError)

        XCTAssertTrue(VPNManager.State.error("fail").isError)
        XCTAssertFalse(VPNManager.State.error("fail").isConnected)

        XCTAssertFalse(VPNManager.State.disconnected.isConnected)
        XCTAssertFalse(VPNManager.State.disconnected.isConnecting)
        XCTAssertFalse(VPNManager.State.disconnected.isError)
    }

    // MARK: - SingBoxDownloadError descriptions

    func testDownloadErrorDescriptions() {
        // Just ensure they don't crash and return non-empty strings
        for err: SingBoxDownloadError in [.extractFailed, .checksumMismatch] {
            let desc = err.errorDescription
            XCTAssertNotNil(desc)
            XCTAssertFalse(desc!.isEmpty)
        }
    }

    private func makeTempSingBox(permissions: Int) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sing-box-\(UUID().uuidString)")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
        return url.path
    }

    // MARK: - System proxy snapshot retention

    private func snapshot(_ service: String, enabled: Bool, server: String, port: String) -> ProxySnapshot {
        ProxySnapshot(service: service, enabled: enabled, server: server, port: port)
    }

    func testGivenNoExistingSnapshotThenTheFreshOneIsKept() {
        let fresh = [snapshot("Wi-Fi", enabled: false, server: "", port: "")]
        let kept = VPNManager.snapshotToRetain(existing: nil, freshlyTaken: fresh)
        XCTAssertEqual(kept, fresh)
    }

    func testGivenEmptyExistingSnapshotThenTheFreshOneIsKept() {
        let fresh = [snapshot("Wi-Fi", enabled: true, server: "10.0.0.1", port: "1080")]
        let kept = VPNManager.snapshotToRetain(existing: [], freshlyTaken: fresh)
        XCTAssertEqual(kept, fresh)
    }

    /// The Proxy Guard case: reconnecting while our own proxy is still applied
    /// must not record that proxy as the state to restore later.
    func testGivenHeldSnapshotThenOurOwnProxyStateIsNotRecorded() {
        let userOriginal = [snapshot("Wi-Fi", enabled: false, server: "", port: "")]
        let ourOwnProxy = [snapshot("Wi-Fi", enabled: true, server: "127.0.0.1", port: "10808")]

        let kept = VPNManager.snapshotToRetain(existing: userOriginal, freshlyTaken: ourOwnProxy)

        XCTAssertEqual(kept, userOriginal, "The user's own settings must survive a reconnect")
        XCTAssertNotEqual(kept, ourOwnProxy, "Rayline must never restore the user onto its own proxy")
    }

    /// A user who genuinely had their own SOCKS proxy configured must get it
    /// back, not have it replaced by ours.
    func testGivenUserHadOwnProxyThenItIsPreservedAcrossReconnect() {
        let userProxy = [snapshot("Wi-Fi", enabled: true, server: "192.168.1.50", port: "3128")]
        let ourOwnProxy = [snapshot("Wi-Fi", enabled: true, server: "127.0.0.1", port: "10808")]

        let kept = VPNManager.snapshotToRetain(existing: userProxy, freshlyTaken: ourOwnProxy)

        XCTAssertEqual(kept, userProxy)
    }
}
