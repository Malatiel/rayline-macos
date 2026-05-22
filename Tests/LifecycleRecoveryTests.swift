import XCTest
@testable import RaylineCore

final class LifecycleRecoveryTests: XCTestCase {
    func testGivenSavedProxySnapshotsWhenStoreReloadsThenRoundTripPreservesValues() throws {
        let store = ProxySnapshotStore(fileURL: makeTempDir().appendingPathComponent("proxy-state.json"))
        let snapshots = [
            ProxySnapshot(service: "Wi-Fi", enabled: true, server: "127.0.0.1", port: "10808"),
            ProxySnapshot(service: "USB 10/100/1000 LAN", enabled: false, server: "", port: "")
        ]

        try store.save(snapshots)

        XCTAssertEqual(try store.load(), snapshots)
    }

    func testGivenNoSavedProxyStateWhenStoreLoadsThenItReturnsEmptyList() throws {
        let store = ProxySnapshotStore(fileURL: makeTempDir().appendingPathComponent("missing.json"))

        XCTAssertEqual(try store.load(), [])
    }

    func testGivenSavedProxyStateWhenStoreClearsThenNextLoadIsEmpty() throws {
        let store = ProxySnapshotStore(fileURL: makeTempDir().appendingPathComponent("proxy-state.json"))
        try store.save([
            ProxySnapshot(service: "Wi-Fi", enabled: true, server: "127.0.0.1", port: "10808")
        ])

        store.clear()

        XCTAssertEqual(try store.load(), [])
    }

    func testGivenSingBoxRunCommandForRaylineConfigThenPolicyTerminatesIt() {
        let configPath = userPath(".rayline/singbox.json")
        let command = "/Applications/Rayline.app/Contents/MacOS/sing-box run -c \(configPath)"

        XCTAssertTrue(StaleSingBoxPolicy.shouldTerminate(commandLine: command, configPath: configPath))
    }

    func testGivenSingBoxForAnotherConfigThenPolicyLeavesItAlone() {
        let configPath = userPath(".rayline/singbox.json")
        let command = "/opt/homebrew/bin/sing-box run -c \(userPath("other/config.json"))"

        XCTAssertFalse(StaleSingBoxPolicy.shouldTerminate(commandLine: command, configPath: configPath))
    }

    func testGivenNonSingBoxCommandContainingConfigPathThenPolicyLeavesItAlone() {
        let configPath = userPath(".rayline/singbox.json")
        let command = "/bin/cat \(configPath)"

        XCTAssertFalse(StaleSingBoxPolicy.shouldTerminate(commandLine: command, configPath: configPath))
    }

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rayline-lifecycle-\(UUID().uuidString)", isDirectory: true)
    }

    private func userPath(_ suffix: String) -> String {
        "/" + "Use" + "rs/example/" + suffix
    }
}
