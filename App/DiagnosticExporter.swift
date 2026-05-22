import Foundation
import Darwin

enum DiagnosticRedactor {
    static func redact(
        _ input: String,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        var output = input

        output = replace(
            #"\b(vless|vmess|ss|trojan)://[^\s<>)"']+"#,
            in: output,
            with: "<redacted-proxy-url>"
        )
        output = replace(
            #"(?i)\b[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}\b"#,
            in: output,
            with: "<redacted-uuid>"
        )
        output = replace(
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: output,
            with: "<redacted-email>"
        )
        output = replace(
            #"(?i)\b(password|passwd|pass|token|secret|uuid|id|key|pbk|sid)=([^&\s]+)"#,
            in: output,
            with: "$1=<redacted>"
        )

        if !homeDirectory.isEmpty {
            output = output.replacingOccurrences(of: homeDirectory, with: "~")
        }

        output = replace(
            #"/(?:Users|private/tmp|tmp)/[^\s<>)"']+"#,
            in: output,
            with: "<redacted-local-path>"
        )

        return output
    }

    private static func replace(_ pattern: String, in input: String, with replacement: String) -> String {
        input.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression]
        )
    }
}

struct DiagnosticExporter {
    static func makeReport(
        appVersion: String,
        build: String,
        state: String,
        hasSingBox: Bool,
        customSingBoxPath: String,
        activeProfile: ProxyConfig?,
        logs: [String],
        now: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "Rayline Diagnostics",
            "Generated: \(formatter.string(from: now))",
            "App: \(appVersion) (\(build))",
            "State: \(state)",
            "sing-box available: \(hasSingBox ? "yes" : "no")",
            "Custom sing-box path: \(customSingBoxPath.isEmpty ? "not set" : customSingBoxPath)"
        ]

        if let activeProfile {
            lines.append("Active profile: \(activeProfile.name)")
            lines.append("Protocol: \(activeProfile.protoName)")
            lines.append("Endpoint: \(activeProfile.server):\(activeProfile.port)")
            if !activeProfile.security.isEmpty {
                lines.append("Security: \(activeProfile.security)")
            }
        } else {
            lines.append("Active profile: none")
        }

        lines.append("")
        lines.append("Logs:")
        lines.append(contentsOf: logs.isEmpty ? ["<empty>"] : logs)

        return DiagnosticRedactor.redact(lines.joined(separator: "\n"))
    }

    static func write(_ report: String, to url: URL) throws {
        let data = Data(report.utf8)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(0o600))
        guard fd >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { close(fd) }

        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { rawBuffer in
                Darwin.write(fd, rawBuffer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if written <= 0 {
                throw CocoaError(.fileWriteUnknown)
            }
            offset += written
        }
    }
}

extension VPNManager {
    func diagnosticsReportText(activeProfile: ProxyConfig? = nil) -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return DiagnosticExporter.makeReport(
            appVersion: appVersion,
            build: build,
            state: String(describing: state),
            hasSingBox: hasSingBox,
            customSingBoxPath: customSingBoxPath,
            activeProfile: activeProfile ?? config,
            logs: logs
        )
    }

    func exportDiagnostics(to url: URL, activeProfile: ProxyConfig? = nil) throws {
        try DiagnosticExporter.write(
            diagnosticsReportText(activeProfile: activeProfile),
            to: url
        )
    }
}
