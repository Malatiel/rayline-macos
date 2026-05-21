import Foundation
import Darwin

struct ProxySnapshotStore: Sendable {
    let fileURL: URL

    static let `default` = ProxySnapshotStore(
        fileURL: VPNManager.installDir.appendingPathComponent("proxy-state.json")
    )

    func save(_ snapshots: [ProxySnapshot]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(snapshots)
        let fd = open(fileURL.path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(0o600))
        guard fd >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { close(fd) }

        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { rawBuffer in
                write(fd, rawBuffer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if written <= 0 {
                throw CocoaError(.fileWriteUnknown)
            }
            offset += written
        }
    }

    func load() throws -> [ProxySnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ProxySnapshot].self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct StaleSingBoxProcess: Equatable {
    let pid: Int32
    let commandLine: String
}

enum StaleSingBoxPolicy {
    static func shouldTerminate(commandLine: String, configPath: String) -> Bool {
        let normalized = commandLine.replacingOccurrences(of: "\\ ", with: " ")
        guard normalized.contains("sing-box") else { return false }
        guard normalized.contains(configPath) else { return false }
        return normalized.contains(" run ")
            || normalized.contains(" run\t")
            || normalized.hasSuffix(" run")
    }
}

struct StaleSingBoxCleaner {
    let configPath: String

    func terminateStaleProcesses() -> [StaleSingBoxProcess] {
        let processes = listProcesses()
            .filter { StaleSingBoxPolicy.shouldTerminate(commandLine: $0.commandLine, configPath: configPath) }

        for process in processes {
            Darwin.kill(process.pid, SIGTERM)
        }
        return processes
    }

    private func listProcesses() -> [StaleSingBoxProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                return nil
            }
            let pidText = String(trimmed[..<firstSpace])
            let commandStart = trimmed[firstSpace...].drop(while: { $0 == " " || $0 == "\t" })
            guard let pid = Int32(pidText), pid != getpid() else {
                return nil
            }
            return StaleSingBoxProcess(pid: pid, commandLine: String(commandStart))
        }
    }
}
