import Foundation

enum AppPaths {
    static let currentDataDirectoryName = ".rayline"
    static let legacyDataDirectoryName = ".veil"

    static let defaultDataDir: URL = dataDirectory(
        home: FileManager.default.homeDirectoryForCurrentUser,
        fileExists: { FileManager.default.fileExists(atPath: $0.path) }
    )

    static func dataDirectory(home: URL, fileExists: (URL) -> Bool) -> URL {
        let current = home.appendingPathComponent(currentDataDirectoryName)
        let legacy = home.appendingPathComponent(legacyDataDirectoryName)

        if !fileExists(current), fileExists(legacy) {
            return legacy
        }
        return current
    }
}
