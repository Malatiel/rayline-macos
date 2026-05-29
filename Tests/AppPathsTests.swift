import XCTest
@testable import RaylineCore

final class AppPathsTests: XCTestCase {
    func testGivenHomeDirectoryThenCurrentRaylineDirectoryIsUsed() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)

        let selected = AppPaths.dataDirectory(home: home)

        XCTAssertEqual(selected.lastPathComponent, ".rayline")
    }

    func testGivenHomeWithTrailingSlashThenRaylineDirectoryIsAppendedOnce() {
        let home = URL(fileURLWithPath: "/tmp/home/", isDirectory: true)

        let selected = AppPaths.dataDirectory(home: home)

        XCTAssertEqual(selected.path, "/tmp/home/.rayline")
    }
}
