import Foundation

// MARK: - Models

enum ProxyProtocol: Equatable { case vless, vmess, shadowsocks, trojan }

struct ProxyConfig {
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

    var isValid: Bool { !server.isEmpty && port > 0 }

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
        switch self {
        case .unknownProtocol: return "Неизвестный протокол (vless/vmess/ss/trojan)"
        case .missingAt:       return "Неверный формат: нет символа @"
        case .invalidPort:     return "Неверный порт"
        case .base64Failed:    return "Ошибка декодирования Base64"
        case .noServer:        return "Не указан сервер"
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
        guard let data = Data(base64Encoded: normalizeBase64(b64)),
              let json = String(data: data, encoding: .utf8) else {
            throw ParseError.base64Failed
        }
        cfg.uuid       = jsonField(json, "id")
        cfg.server     = jsonField(json, "add")
        cfg.port       = Int(jsonField(json, "port")) ?? 0
        let net        = jsonField(json, "net");  cfg.network = net.isEmpty ? "tcp" : net
        cfg.path       = jsonField(json, "path")
        cfg.host       = jsonField(json, "host")
        cfg.sni        = jsonField(json, "sni")
        cfg.security   = jsonField(json, "tls")
        cfg.fp         = jsonField(json, "fp")
        cfg.encryption = "auto"
        let ps = jsonField(json, "ps")
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
            cfg.port   = Int(String(hp[end.upperBound...])) ?? 0
            return
        }
        if let c = hp.range(of: ":", options: .backwards) {
            cfg.server = String(hp[..<c.lowerBound])
            cfg.port   = Int(String(hp[c.upperBound...])) ?? 0
        } else { cfg.server = hp }
        if cfg.server.isEmpty { throw ParseError.noServer }
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

    /// Minimal JSON string-field extractor (no dependencies)
    static func jsonField(_ json: String, _ key: String) -> String {
        guard let kr = json.range(of: "\"\(key)\"") else { return "" }
        var i = kr.upperBound
        while i < json.endIndex, json[i] == " " || json[i] == ":" { i = json.index(after: i) }
        guard i < json.endIndex else { return "" }
        if json[i] == "\"" {
            i = json.index(after: i)
            var val = ""
            while i < json.endIndex, json[i] != "\"" {
                if json[i] == "\\" { i = json.index(after: i); if i < json.endIndex { val.append(json[i]) } }
                else { val.append(json[i]) }
                i = json.index(after: i)
            }
            return val
        } else {
            var val = ""
            while i < json.endIndex, json[i] != "," && json[i] != "}" { val.append(json[i]); i = json.index(after: i) }
            return val.trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - sing-box config generation

extension ProxyConfig {

    func toSingBoxConfig() -> String {
        var j = "{\n"
        j += "  \"log\": {\"level\": \"info\"},\n"
        j += "  \"inbounds\": [{\n"
        j += "    \"type\": \"socks\", \"listen\": \"127.0.0.1\", \"listen_port\": 10808,\n"
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
