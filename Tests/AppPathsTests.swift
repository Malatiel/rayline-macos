import XCTest
@testable import RaylineCore

final class AppPathsTests: XCTestCase {
    func testGivenNoExistingDataDirectoriesThenCurrentRaylineDirectoryIsUsed() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)

        let selected = AppPaths.dataDirectory(home: home, fileExists: { _ in false })

        XCTAssertEqual(selected.lastPathComponent, ".rayline")
    }

    func testGivenLegacyVeilDataAndNoRaylineDataThenLegacyDirectoryIsUsed() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)

        let selected = AppPaths.dataDirectory(home: home) { url in
            url.lastPathComponent == ".veil"
        }

        XCTAssertEqual(selected.lastPathComponent, ".veil")
    }

    func testGivenBothLegacyAndCurrentDataThenCurrentRaylineDirectoryWins() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)

        let selected = AppPaths.dataDirectory(home: home) { url in
            url.lastPathComponent == ".veil" || url.lastPathComponent == ".rayline"
        }

        XCTAssertEqual(selected.lastPathComponent, ".rayline")
    }
}
