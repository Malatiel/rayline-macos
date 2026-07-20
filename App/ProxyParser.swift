import Foundation

// MARK: - Models

enum ProxyProtocol: String, Equatable, Codable, Sendable { case vless, vmess, shadowsocks, trojan }

struct ProxyConfig: Codable, Identifiable, Equatable, Sendable {
    var id:            UUID   = UUID()
    var proto:         ProxyProtocol
    var uuid:          String = ""
    var server:        String = ""
    var port:          Int    = 0
    var name:          String = ""
    var security:      String = "none"
    var network:       String = "tcp"
    var sni:           String = ""
    var host:          String = ""
    var path:          String = "/"
    var fp:            String = ""
    var pbk:           String = ""
    var shortId:       String = ""
    var encryption:    String = ""
    var method:        String = ""   // Shadowsocks cipher
    var allowInsecure: Bool   = false
    var sourceId:      UUID?
    var sourceName:    String?
    var latencyMs:     Int?
    var latencyUpdatedAt: Date?

    var isValid: Bool { !server.isEmpty && (1...65535).contains(port) }

    /// Whether a link rebuilt from this profile would carry a secret.
    ///
    /// `uuid` holds the VLESS/VMess id and doubles as the Shadowsocks and Trojan
    /// password, so it is the one field that turns a shareable link into a
    /// credential. Anything reconstructing a URL for the user to pass around
    /// should check this first.
    var carriesCredentials: Bool { !uuid.isEmpty }

    var protoName: String {
        switch proto {
        case .vless:        return "VLESS"
        case .vmess:        return "VMess"
        case .shadowsocks:  return "Shadowsocks"
        case .trojan:       return "Trojan"
        }
    }
}

// MARK: - Errors

enum ParseError: LocalizableError {
    case unknownProtocol, missingAt, invalidPort, base64Failed, noServer
    var localizedMessage: LocalizedMessage {
        switch self {
        case .unknownProtocol: return LocalizedMessage(ru: "Неизвестный протокол (vless/vmess/ss/trojan)",
                                                       en: "Unknown protocol (vless/vmess/ss/trojan)")
        case .missingAt:       return LocalizedMessage(ru: "Неверный формат: нет символа @",
                                                       en: "Invalid format: missing @ symbol")
        case .invalidPort:     return LocalizedMessage(ru: "Неверный порт", en: "Invalid port")
        case .base64Failed:    return LocalizedMessage(ru: "Ошибка декодирования Base64", en: "Base64 decoding failed")
        case .noServer:        return LocalizedMessage(ru: "Не указан сервер", en: "No server specified")
        }
    }
}

// MARK: - Parser

enum ProxyParser {

    static func parse(_ uri: String) throws -> ProxyConfig {
        // Strip all whitespace/newlines — a valid proxy URL never contains them,
        // but copy-paste from messengers often introduces line breaks.
        let u = uri.components(separatedBy: .whitespacesAndNewlines).joined()
        if u.hasPrefix("vless://")  { return try parseVless(u) }
        if u.hasPrefix("vmess://")  { return try parseVmess(u) }
        if u.hasPrefix("ss://")     { return try parseSS(u) }
        if u.hasPrefix("trojan://") { return try parseTrojan(u) }
        throw ParseError.unknownProtocol
    }

    // MARK: VLESS
    private static func parseVless(_ uri: String) throws -> ProxyConfig {
        var cfg  = ProxyConfig(proto: .vless)
        var rest = String(uri.dropFirst("vless://".count))

        if let r = rest.range(of: "#") {
            cfg.name = String(rest[r.upperBound...]).removingPercentEncoding ?? ""
            rest = String(rest[..<r.lowerBound])
        }
        var params: [String: String] = [:]
        if let r = rest.range(of: "?") {
            params = parseQuery(String(rest[r.upperBound...]))
            rest   = String(rest[..<r.lowerBound])
        }
        guard let at = rest.range(of: "@") else { throw ParseError.missingAt }
        cfg.uuid = String(rest[..<at.lowerBound])
        try parseHostPort(String(rest[at.upperBound...]), into: &cfg)

        cfg.encryption    = params["encryption"]    ?? "none"
        cfg.security      = params["security"]      ?? "none"
        cfg.network       = params["type"]           ?? "tcp"
        cfg.sni           = params["sni"]            ?? ""
        cfg.host          = params["host"]           ?? ""
        cfg.path          = params["path"]           ?? "/"
        cfg.fp            = params["fp"]             ?? ""
        cfg.pbk           = params["pbk"]            ?? ""
        cfg.shortId       = params["sid"]            ?? ""
        cfg.allowInsecure = params["allowInsecure"] == "1" || params["allowInsecure"] == "true"
        if cfg.name.isEmpty { cfg.name = cfg.server }
        return cfg
    }

    // MARK: VMess
    private static func parseVmess(_ uri: String) throws -> ProxyConfig {
        var cfg = ProxyConfig(proto: .vmess)
        var b64 = String(uri.dropFirst("vmess://".count))
        if let r = b64.range(of: "#") {
            cfg.name = String(b64[r.upperBound...]).removingPercentEncoding ?? ""
            b64 = String(b64[..<r.lowerBound])
        }
        guard let data = Data(base64Encoded: normalizeBase64(b64)) else {
            throw ParseError.base64Failed
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw ParseError.base64Failed
        }

        cfg.uuid       = jsonString(json, "id")
        cfg.server     = jsonString(json, "add")
        cfg.port       = try jsonPort(json, "port")
        let net        = jsonString(json, "net");  cfg.network = net.isEmpty ? "tcp" : net
        cfg.path       = jsonString(json, "path")
        cfg.host       = jsonString(json, "host")
        cfg.sni        = jsonString(json, "sni")
        cfg.security   = jsonString(json, "tls")
        cfg.fp         = jsonString(json, "fp")
        cfg.encryption = "auto"
        let ps = jsonString(json, "ps")
        cfg.name = cfg.name.isEmpty ? (ps.isEmpty ? cfg.server : ps) : cfg.name
        if cfg.server.isEmpty { throw ParseError.noServer }
        return cfg
    }

    // MARK: Shadowsocks
    private static func parseSS(_ uri: String) throws -> ProxyConfig {
        var cfg  = ProxyConfig(proto: .shadowsocks)
        var rest = String(uri.dropFirst("ss://".count))
        if let r = rest.range(of: "#") {
            cfg.name = String(rest[r.upperBound...]).removingPercentEncoding ?? ""
            rest = String(rest[..<r.lowerBound])
        }
        if let r = rest.range(of: "?") { rest = String(rest[..<r.lowerBound]) }

        if let at = rest.range(of: "@") {
            // SIP002
            let userinfo = String(rest[..<at.lowerBound])
            let hostport = String(rest[at.upperBound...])
            let decoded  = decode64orURL(userinfo)
            if let c = decoded.range(of: ":") {
                cfg.method = String(decoded[..<c.lowerBound])
                cfg.uuid   = String(decoded[c.upperBound...])
            }
            try parseHostPort(hostport, into: &cfg)
        } else {
            // Legacy
            let decoded = decode64orURL(rest)
            if let at = decoded.range(of: "@", options: .backwards) {
                let userinfo = String(decoded[..<at.lowerBound])
                let hostport = String(decoded[at.upperBound...])
                if let c = userinfo.range(of: ":") {
                    cfg.method = String(userinfo[..<c.lowerBound])
                    cfg.uuid   = String(userinfo[c.upperBound...])
                }
                try parseHostPort(hostport, into: &cfg)
            }
        }
        cfg.security = "none"; cfg.network = "tcp"
        if cfg.name.isEmpty { cfg.name = cfg.server }
        return cfg
    }

    // MARK: Trojan
    private static func parseTrojan(_ uri: String) throws -> ProxyConfig {
        var cfg  = ProxyConfig(proto: .trojan)
        var rest = String(uri.dropFirst("trojan://".count))
        if let r = rest.range(of: "#") {
            cfg.name = String(rest[r.upperBound...]).removingPercentEncoding ?? ""
            rest = String(rest[..<r.lowerBound])
        }
        var params: [String: String] = [:]
        if let r = rest.range(of: "?") {
            params = parseQuery(String(rest[r.upperBound...]))
            rest   = String(rest[..<r.lowerBound])
        }
        guard let at = rest.range(of: "@") else { throw ParseError.missingAt }
        cfg.uuid = (String(rest[..<at.lowerBound])).removingPercentEncoding ?? ""
        try parseHostPort(String(rest[at.upperBound...]), into: &cfg)

        cfg.security      = params["security"]    ?? "tls"
        cfg.sni           = params["sni"]         ?? ""
        cfg.network       = params["type"]        ?? "tcp"
        cfg.path          = params["path"]        ?? "/"
        cfg.host          = params["host"]        ?? ""
        cfg.fp            = params["fp"]          ?? ""
        cfg.allowInsecure = params["allowInsecure"] == "1" || params["allowInsecure"] == "true"
        if cfg.name.isEmpty { cfg.name = cfg.server }
        return cfg
    }

    // MARK: Helpers

    private static func parseHostPort(_ s: String, into cfg: inout ProxyConfig) throws {
        let hp = s
        if hp.hasPrefix("["), let end = hp.range(of: "]:") {
            cfg.server = String(hp[hp.index(after: hp.startIndex)..<end.lowerBound])
            cfg.port = try parsePort(String(hp[end.upperBound...]))
            if cfg.server.isEmpty { throw ParseError.noServer }
            return
        }
        if let c = hp.range(of: ":", options: .backwards) {
            cfg.server = String(hp[..<c.lowerBound])
            cfg.port = try parsePort(String(hp[c.upperBound...]))
        } else { cfg.server = hp }
        if cfg.server.isEmpty { throw ParseError.noServer }
    }

    private static func parsePort(_ s: String) throws -> Int {
        guard let port = Int(s), (1...65535).contains(port) else {
            throw ParseError.invalidPort
        }
        return port
    }

    private static func parseQuery(_ qs: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in qs.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let k = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let v = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                result[k] = v
            }
        }
        return result
    }

    private static func normalizeBase64(_ s: String) -> String {
        var n = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while n.count % 4 != 0 { n += "=" }
        return n
    }

    private static func decode64orURL(_ s: String) -> String {
        if let d = Data(base64Encoded: normalizeBase64(s)),
           let t = String(data: d, encoding: .utf8) { return t }
        return s.removingPercentEncoding ?? s
    }

    private static func jsonString(_ json: [String: Any], _ key: String) -> String {
        json[key] as? String ?? ""
    }

    private static func jsonPort(_ json: [String: Any], _ key: String) throws -> Int {
        if let string = json[key] as? String {
            return try parsePort(string)
        }
        if let number = json[key] as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                throw ParseError.invalidPort
            }
            return try parsePort(number.stringValue)
        }
        throw ParseError.invalidPort
    }
}

// MARK: - sing-box config generation

/// How the failover group probes its members.
///
/// sing-box measures each member by fetching `testURL` through it, on repeat.
/// That is real, recurring traffic to a third party through every configured
/// server, which is why failover is opt-in rather than the default.
struct FailoverSettings: Equatable {
    let testURL: String
    let interval: String
    /// Milliseconds a member must beat the current one by before switching, so
    /// two similar servers do not trade places constantly.
    let tolerance: Int

    static let `default` = FailoverSettings(
        testURL: "https://www.gstatic.com/generate_204",
        interval: "3m",
        tolerance: 50
    )
}

/// Encodable model of the subset of sing-box configuration Rayline generates.
/// Going through JSONEncoder means all escaping is handled, so server names,
/// passwords, and paths containing quotes, slashes, or control characters
/// always produce valid JSON.
struct SingBoxConfig: Encodable {
    let log: Log
    let inbounds: [Inbound]
    let outbounds: [Outbound]
    let route: Route

    /// Outbound tags. Route rules address outbounds by tag, so both the proxy
    /// and the direct outbound need one.
    static let proxyTag  = "proxy"
    static let directTag = "direct"

    struct Log: Encodable { let level: String }

    struct Inbound: Encodable {
        let type: String
        let listen: String
        let listen_port: Int
        let sniff: Bool
        let sniff_override_destination: Bool
    }

    struct Outbound: Encodable {
        let type: String
        var tag: String?
        // The direct outbound has no endpoint, so these are optional even
        // though every proxy outbound sets them.
        var server: String?
        var server_port: Int?
        var uuid: String?       // VLESS / VMess
        var flow: String?       // VLESS Reality
        var security: String?   // VMess cipher
        var method: String?     // Shadowsocks cipher
        var password: String?   // Shadowsocks / Trojan
        var tls: TLS?
        var transport: Transport?

        // urltest group only: the member tags it chooses between, plus how it
        // probes them.
        var outbounds: [String]?
        var url: String?
        var interval: String?
        var tolerance: Int?
    }

    struct Route: Encodable {
        let rules: [Rule]
        let `final`: String
    }

    struct Rule: Encodable {
        let ip_is_private: Bool
        let outbound: String
    }

    struct TLS: Encodable {
        let enabled: Bool
        let server_name: String
        var insecure: Bool?
        var utls: UTLS?
        var reality: Reality?
    }

    struct UTLS: Encodable {
        let enabled: Bool
        let fingerprint: String
    }

    struct Reality: Encodable {
        let enabled: Bool
        let public_key: String
        let short_id: String
    }

    struct Transport: Encodable {
        let type: String
        var path: String?
        var service_name: String?
        var headers: [String: String]?
    }
}

extension ProxyConfig {

    func toSingBoxConfig(socksPort: Int = VPNManager.socksPort) -> String {
        var proxy = singBoxOutbound()
        proxy.tag = SingBoxConfig.proxyTag

        // Traffic to private and loopback addresses goes out directly instead of
        // through the proxy, so the local network (router page, NAS, printer)
        // stays reachable while connected. This matches on the destination IP,
        // so it covers literal addresses; local *hostnames* depend on how the
        // requesting app resolves them and are not guaranteed.
        let direct = SingBoxConfig.Outbound(
            type: "direct",
            tag: SingBoxConfig.directTag
        )

        let config = SingBoxConfig(
            log: .init(level: "info"),
            inbounds: [
                .init(
                    type: "socks",
                    listen: "127.0.0.1",
                    listen_port: socksPort,
                    sniff: true,
                    sniff_override_destination: true
                )
            ],
            outbounds: [proxy, direct],
            route: .init(
                rules: [
                    .init(ip_is_private: true, outbound: SingBoxConfig.directTag)
                ],
                final: SingBoxConfig.proxyTag
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    func singBoxOutbound() -> SingBoxConfig.Outbound {
        switch proto {
        case .vless:
            var outbound = SingBoxConfig.Outbound(type: "vless", server: server, server_port: port)
            outbound.uuid = uuid
            let useReality = security == "reality"
            let useTLS = security == "tls" || useReality
            if useReality { outbound.flow = "xtls-rprx-vision" }
            if useTLS {
                var tls = SingBoxConfig.TLS(enabled: true, server_name: sni.isEmpty ? server : sni)
                if allowInsecure { tls.insecure = true }
                if !fp.isEmpty { tls.utls = .init(enabled: true, fingerprint: fp) }
                if useReality { tls.reality = .init(enabled: true, public_key: pbk, short_id: shortId) }
                outbound.tls = tls
            }
            outbound.transport = singBoxTransport()
            return outbound

        case .vmess:
            var outbound = SingBoxConfig.Outbound(type: "vmess", server: server, server_port: port)
            outbound.uuid = uuid
            outbound.security = encryption.isEmpty ? "auto" : encryption
            if security == "tls" {
                outbound.tls = .init(enabled: true, server_name: sni.isEmpty ? server : sni)
            }
            outbound.transport = singBoxTransport()
            return outbound

        case .shadowsocks:
            var outbound = SingBoxConfig.Outbound(type: "shadowsocks", server: server, server_port: port)
            outbound.method = method.isEmpty ? "aes-128-gcm" : method
            outbound.password = uuid
            return outbound

        case .trojan:
            var outbound = SingBoxConfig.Outbound(type: "trojan", server: server, server_port: port)
            outbound.password = uuid
            if security == "tls" || security.isEmpty {
                var tls = SingBoxConfig.TLS(enabled: true, server_name: sni.isEmpty ? server : sni)
                if allowInsecure { tls.insecure = true }
                if !fp.isEmpty { tls.utls = .init(enabled: true, fingerprint: fp) }
                outbound.tls = tls
            }
            // Trojan only carries a WebSocket transport in this client.
            if network == "ws" { outbound.transport = singBoxWebSocketTransport() }
            return outbound
        }
    }

    /// Config that spreads across several profiles and lets sing-box move to a
    /// working one on its own.
    ///
    /// Returns `nil` for fewer than two profiles: a group of one has nothing to
    /// fail over to, and would only add recurring probe traffic for nothing.
    /// The group carries the `proxy` tag so routing is identical to the single
    /// profile case — only what sits behind that tag changes.
    static func singBoxFailoverConfig(
        profiles: [ProxyConfig],
        socksPort: Int = VPNManager.socksPort,
        settings: FailoverSettings = .default
    ) -> String? {
        guard profiles.count >= 2 else { return nil }

        var members: [SingBoxConfig.Outbound] = []
        var memberTags: [String] = []
        for (index, profile) in profiles.enumerated() {
            var outbound = profile.singBoxOutbound()
            let tag = "\(SingBoxConfig.proxyTag)-\(index)"
            outbound.tag = tag
            members.append(outbound)
            memberTags.append(tag)
        }

        var group = SingBoxConfig.Outbound(type: "urltest", tag: SingBoxConfig.proxyTag)
        group.outbounds = memberTags
        group.url = settings.testURL
        group.interval = settings.interval
        group.tolerance = settings.tolerance

        let direct = SingBoxConfig.Outbound(
            type: "direct",
            tag: SingBoxConfig.directTag
        )

        let config = SingBoxConfig(
            log: .init(level: "info"),
            inbounds: [
                .init(
                    type: "socks",
                    listen: "127.0.0.1",
                    listen_port: socksPort,
                    sniff: true,
                    sniff_override_destination: true
                )
            ],
            outbounds: [group] + members + [direct],
            route: .init(
                rules: [
                    .init(ip_is_private: true, outbound: SingBoxConfig.directTag)
                ],
                final: SingBoxConfig.proxyTag
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func singBoxTransport() -> SingBoxConfig.Transport? {
        switch network {
        case "ws":   return singBoxWebSocketTransport()
        case "grpc": return .init(type: "grpc", service_name: path)
        case "h2":   return .init(type: "http", path: path.isEmpty ? "/" : path)
        default:     return nil
        }
    }

    private func singBoxWebSocketTransport() -> SingBoxConfig.Transport {
        var transport = SingBoxConfig.Transport(type: "ws", path: path.isEmpty ? "/" : path)
        if !host.isEmpty { transport.headers = ["Host": host] }
        return transport
    }
}

// MARK: - URL export

/// Encodable model of the legacy VMess share-link JSON payload. All fields are
/// strings, matching the de-facto VMess link format consumed by `parseVmess`.
private struct VmessLink: Encodable {
    let v: String
    let ps: String
    let add: String
    let port: String
    let id: String
    let aid: String
    let net: String
    let type: String
    let host: String
    let path: String
    let tls: String
    let sni: String
    let fp: String
}

extension ProxyConfig {

    func toURL() -> String {
        switch proto {
        case .vless:   return vlessURL()
        case .vmess:   return vmessURL()
        case .shadowsocks: return ssURL()
        case .trojan:  return trojanURL()
        }
    }

    // MARK: Private

    private func vlessURL() -> String {
        var params: [(String, String)] = []
        if !encryption.isEmpty && encryption != "none" { params.append(("encryption", encryption)) }
        params.append(("security", security))
        params.append(("type", network))
        if !sni.isEmpty  { params.append(("sni", sni)) }
        if !host.isEmpty { params.append(("host", host)) }
        if path != "/" && !path.isEmpty { params.append(("path", path)) }
        if !fp.isEmpty   { params.append(("fp", fp)) }
        if !pbk.isEmpty  { params.append(("pbk", pbk)) }
        if !shortId.isEmpty { params.append(("sid", shortId)) }
        if allowInsecure { params.append(("allowInsecure", "1")) }
        let qs = params.map { "\($0.0)=\(urlEncode($0.1))" }.joined(separator: "&")
        return "vless://\(urlEncode(uuid))@\(serverHostPort())?\(qs)#\(urlEncode(name))"
    }

    private func vmessURL() -> String {
        let link = VmessLink(
            v: "2",
            ps: name,
            add: server,
            port: "\(port)",
            id: uuid,
            aid: "0",
            net: network,
            type: "none",
            host: host,
            path: path,
            tls: security,
            sni: sni,
            fp: fp
        )
        guard let data = try? JSONEncoder().encode(link) else { return "vmess://" }
        return "vmess://\(data.base64EncodedString())"
    }

    private func ssURL() -> String {
        let userinfo = "\(method):\(uuid)"
        let b64 = Data(userinfo.utf8).base64EncodedString()
        return "ss://\(b64)@\(serverHostPort())#\(urlEncode(name))"
    }

    private func trojanURL() -> String {
        var params: [(String, String)] = []
        params.append(("security", security.isEmpty ? "tls" : security))
        if !sni.isEmpty  { params.append(("sni", sni)) }
        params.append(("type", network))
        if path != "/" && !path.isEmpty { params.append(("path", path)) }
        if !host.isEmpty { params.append(("host", host)) }
        if !fp.isEmpty   { params.append(("fp", fp)) }
        if allowInsecure { params.append(("allowInsecure", "1")) }
        let qs = params.map { "\($0.0)=\(urlEncode($0.1))" }.joined(separator: "&")
        return "trojan://\(urlEncode(uuid))@\(serverHostPort())?\(qs)#\(urlEncode(name))"
    }

    private func serverHostPort() -> String {
        if server.contains(":") { return "[\(server)]:\(port)" } // IPv6
        return "\(server):\(port)"
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#@!$&'()*+,;=[]/?")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

}
