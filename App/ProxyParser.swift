import Foundation

// MARK: - Models

enum ProxyProtocol: String, Equatable, Codable { case vless, vmess, shadowsocks, trojan }

struct ProxyConfig: Codable, Identifiable, Equatable {
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

    var isValid: Bool { !server.isEmpty && (1...65535).contains(port) }

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

enum ParseError: LocalizedError {
    case unknownProtocol, missingAt, invalidPort, base64Failed, noServer
    var errorDescription: String? {
        let L = LanguageManager.shared
        switch self {
        case .unknownProtocol: return L.t("Неизвестный протокол (vless/vmess/ss/trojan)",
                                          "Unknown protocol (vless/vmess/ss/trojan)")
        case .missingAt:       return L.t("Неверный формат: нет символа @",
                                          "Invalid format: missing @ symbol")
        case .invalidPort:     return L.t("Неверный порт", "Invalid port")
        case .base64Failed:    return L.t("Ошибка декодирования Base64", "Base64 decoding failed")
        case .noServer:        return L.t("Не указан сервер", "No server specified")
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

extension ProxyConfig {

    func toSingBoxConfig(socksPort: Int = VPNManager.socksPort) -> String {
        var j = "{\n"
        j += "  \"log\": {\"level\": \"info\"},\n"
        j += "  \"inbounds\": [{\n"
        j += "    \"type\": \"socks\", \"listen\": \"127.0.0.1\", \"listen_port\": \(socksPort),\n"
        j += "    \"sniff\": true, \"sniff_override_destination\": true\n"
        j += "  }],\n"
        j += "  \"outbounds\": [{\n"

        switch proto {
        case .vless:
            j += "    \"type\": \"vless\",\n"
            j += "    \"server\": \"\(esc(server))\", \"server_port\": \(port),\n"
            j += "    \"uuid\": \"\(esc(uuid))\""
            let useReality = security == "reality"
            let useTLS     = security == "tls" || useReality
            if useReality { j += ",\n    \"flow\": \"xtls-rprx-vision\"" }
            if useTLS {
                j += ",\n    \"tls\": { \"enabled\": true, \"server_name\": \"\(esc(sni.isEmpty ? server : sni))\""
                if allowInsecure { j += ", \"insecure\": true" }
                if !fp.isEmpty   { j += ", \"utls\": {\"enabled\": true, \"fingerprint\": \"\(esc(fp))\"}" }
                if useReality    { j += ", \"reality\": {\"enabled\": true, \"public_key\": \"\(esc(pbk))\", \"short_id\": \"\(esc(shortId))\"}" }
                j += " }"
            }
            j += transportBlock()

        case .vmess:
            j += "    \"type\": \"vmess\",\n"
            j += "    \"server\": \"\(esc(server))\", \"server_port\": \(port),\n"
            j += "    \"uuid\": \"\(esc(uuid))\", \"security\": \"\(esc(encryption.isEmpty ? "auto" : encryption))\""
            if security == "tls" {
                j += ",\n    \"tls\": { \"enabled\": true, \"server_name\": \"\(esc(sni.isEmpty ? server : sni))\" }"
            }
            j += transportBlock()

        case .shadowsocks:
            j += "    \"type\": \"shadowsocks\",\n"
            j += "    \"server\": \"\(esc(server))\", \"server_port\": \(port),\n"
            j += "    \"method\": \"\(esc(method.isEmpty ? "aes-128-gcm" : method))\",\n"
            j += "    \"password\": \"\(esc(uuid))\""

        case .trojan:
            j += "    \"type\": \"trojan\",\n"
            j += "    \"server\": \"\(esc(server))\", \"server_port\": \(port),\n"
            j += "    \"password\": \"\(esc(uuid))\""
            if security == "tls" || security.isEmpty {
                j += ",\n    \"tls\": { \"enabled\": true, \"server_name\": \"\(esc(sni.isEmpty ? server : sni))\""
                if allowInsecure { j += ", \"insecure\": true" }
                if !fp.isEmpty   { j += ", \"utls\": {\"enabled\": true, \"fingerprint\": \"\(esc(fp))\"}" }
                j += " }"
            }
            if network == "ws" { j += wsBlock() }
        }

        j += "\n  }]\n}\n"
        return j
    }

    private func transportBlock() -> String {
        switch network {
        case "ws":   return wsBlock()
        case "grpc": return ",\n    \"transport\": {\"type\": \"grpc\", \"service_name\": \"\(esc(path))\"}"
        case "h2":   return ",\n    \"transport\": {\"type\": \"http\", \"path\": \"\(esc(path.isEmpty ? "/" : path))\"}"
        default:     return ""
        }
    }

    private func wsBlock() -> String {
        var b = ",\n    \"transport\": {\"type\": \"ws\", \"path\": \"\(esc(path.isEmpty ? "/" : path))\""
        if !host.isEmpty { b += ", \"headers\": {\"Host\": \"\(esc(host))\"}" }
        b += "}"
        return b
    }

    private func esc(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out += String(scalar)
                }
            }
        }
        return out
    }
}

// MARK: - URL export

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
        var j = "{"
        j += "\"v\":\"2\""
        j += ",\"ps\":\"\(esc(name))\""
        j += ",\"add\":\"\(esc(server))\""
        j += ",\"port\":\"\(port)\""
        j += ",\"id\":\"\(esc(uuid))\""
        j += ",\"aid\":\"0\""
        j += ",\"net\":\"\(esc(network))\""
        j += ",\"type\":\"none\""
        j += ",\"host\":\"\(esc(host))\""
        j += ",\"path\":\"\(esc(path))\""
        j += ",\"tls\":\"\(esc(security))\""
        j += ",\"sni\":\"\(esc(sni))\""
        j += ",\"fp\":\"\(esc(fp))\""
        j += "}"
        let b64 = Data(j.utf8).base64EncodedString()
        return "vmess://\(b64)"
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
