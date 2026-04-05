import XCTest
@testable import VeilCore

@MainActor
final class VPNManagerTests: XCTestCase {

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
        let vpn = VPNManager()
        let before = vpn.logs.count
        vpn.addLog("test message")
        XCTAssertEqual(vpn.logs.count, before + 1)
        XCTAssertTrue(vpn.logs.last!.contains("test message"))
    }

    func testAddLogTimestamp() {
        let vpn = VPNManager()
        vpn.addLog("hello")
        // Should contain HH:mm:ss prefix
        let log = vpn.logs[0]
        let parts = log.split(separator: " ", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains(":"), "First part should be a timestamp")
    }

    func testLogCapAt300() {
        let vpn = VPNManager()
        for i in 0..<350 {
            vpn.addLog("line \(i)")
        }
        XCTAssertEqual(vpn.logs.count, 300)
        XCTAssertTrue(vpn.logs.first!.contains("line 50"), "Oldest 50 entries should be evicted")
        XCTAssertTrue(vpn.logs.last!.contains("line 349"))
    }

    func testClearLog() {
        let vpn = VPNManager()
        vpn.addLog("a")
        vpn.addLog("b")
        vpn.clearLog()
        XCTAssertTrue(vpn.logs.isEmpty)
    }

    // MARK: - Initial state

    func testInitialState() {
        let vpn = VPNManager()
        XCTAssertFalse(vpn.state.isConnected)
        XCTAssertFalse(vpn.state.isConnecting)
        XCTAssertNil(vpn.config)
        XCTAssertNil(vpn.pingMs)
        XCTAssertEqual(vpn.packetsSent, 0)
        XCTAssertEqual(vpn.packetsRecv, 0)
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

        XCTAssertTrue(VPNManager.State.error("fail").isError)
        XCTAssertFalse(VPNManager.State.error("fail").isConnected)

        XCTAssertFalse(VPNManager.State.disconnected.isConnected)
        XCTAssertFalse(VPNManager.State.disconnected.isConnecting)
        XCTAssertFalse(VPNManager.State.disconnected.isError)
    }

    // MARK: - SingBoxDownloadError descriptions

    func testDownloadErrorDescriptions() {
        // Just ensure they don't crash and return non-empty strings
        for err: SingBoxDownloadError in [.parseError, .assetNotFound, .extractFailed, .checksumMismatch] {
            let desc = err.errorDescription
            XCTAssertNotNil(desc)
            XCTAssertFalse(desc!.isEmpty)
        }
    }
}
