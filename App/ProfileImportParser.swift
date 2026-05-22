import Foundation

struct ProfileImportFailure: Equatable {
    let input: String
    let message: String
}

struct ProfileImportResult: Equatable {
    let profiles: [ProxyConfig]
    let failures: [ProfileImportFailure]

    var validCount: Int { profiles.count }
    var failureCount: Int { failures.count }
}

enum ProfileImportParser {
    static let maxInputBytes = 2_000_000

    static func parse(_ text: String) -> ProfileImportResult {
        guard text.utf8.count <= maxInputBytes else {
            return ProfileImportResult(
                profiles: [],
                failures: [ProfileImportFailure(input: "", message: "Import text is too large")]
            )
        }

        let candidates = importCandidates(from: text)
        var profiles: [ProxyConfig] = []
        var failures: [ProfileImportFailure] = []

        for candidate in candidates {
            do {
                let profile = try ProxyParser.parse(candidate)
                if profile.isValid {
                    profiles.append(profile)
                } else {
                    failures.append(ProfileImportFailure(input: candidate, message: "Link has no server or port"))
                }
            } catch {
                failures.append(ProfileImportFailure(input: candidate, message: error.localizedDescription))
            }
        }

        return ProfileImportResult(profiles: profiles, failures: failures)
    }

    private static func importCandidates(from text: String) -> [String] {
        var sources = [text]
        if let decoded = decodeSubscriptionBody(text) {
            sources.append(decoded)
        }

        var seen = Set<String>()
        var candidates: [String] = []
        for source in sources {
            for candidate in proxyURLs(in: source) {
                if seen.insert(candidate).inserted {
                    candidates.append(candidate)
                }
            }
        }

        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        if candidates.isEmpty,
           isSupportedProxyURL(compact),
           seen.insert(compact).inserted {
            candidates.append(compact)
        }

        return candidates
    }

    private static func proxyURLs(in text: String) -> [String] {
        let pattern = #"(?i)(vless|vmess|ss|trojan)://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func decodeSubscriptionBody(_ text: String) -> String? {
        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard compact.count >= 8, !isSupportedProxyURL(compact) else { return nil }
        guard compact.range(of: #"^[A-Za-z0-9+/_=-]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        var normalized = compact
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 {
            normalized += "="
        }

        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8),
              decoded.range(of: #"(?i)(vless|vmess|ss|trojan)://"#, options: .regularExpression) != nil else {
            return nil
        }
        return decoded
    }

    private static func isSupportedProxyURL(_ text: String) -> Bool {
        text.hasPrefix("vless://")
            || text.hasPrefix("vmess://")
            || text.hasPrefix("ss://")
            || text.hasPrefix("trojan://")
    }
}

struct ProfileBatchAddResult: Equatable {
    let addedCount: Int
    let skippedDuplicateCount: Int
}

extension ProxyConfig {
    func hasSameConnection(as other: ProxyConfig) -> Bool {
        proto == other.proto
            && uuid == other.uuid
            && server == other.server
            && port == other.port
            && security == other.security
            && network == other.network
            && sni == other.sni
            && host == other.host
            && path == other.path
            && fp == other.fp
            && pbk == other.pbk
            && shortId == other.shortId
            && encryption == other.encryption
            && method == other.method
            && allowInsecure == other.allowInsecure
    }
}
