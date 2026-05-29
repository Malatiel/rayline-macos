import Foundation

enum AppPaths {
    static let currentDataDirectoryName = ".rayline"

    static let defaultDataDir: URL = dataDirectory(
        home: FileManager.default.homeDirectoryForCurrentUser
    )

    static func dataDirectory(home: URL) -> URL {
        home.appendingPathComponent(currentDataDirectoryName)
    }
}
