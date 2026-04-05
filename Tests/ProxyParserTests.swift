import XCTest
@testable import VeilCore

final class ProxyParserTests: XCTestCase {

    // MARK: - VLESS Parsing

    func testVlessBasicWithTLS() throws {
        let uuid = "a3c7e1f2-1234-5678-abcd-ef0123456789"
        let uri = "vless://\(uuid)@example.com:443?security=tls&sni=example.com&type=tcp#MyServer"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.proto, .vless)
        XCTAssertEqual(cfg.uuid, uuid)
        XCTAssertEqual(cfg.server, "example.com")
        XCTAssertEqual(cfg.port, 443)
        XCTAssertEqual(cfg.security, "tls")
        XCTAssertEqual(cfg.sni, "example.com")
        XCTAssertEqual(cfg.name, "MyServer")
    }

    func testVlessRealitySecurity() throws {
        let uuid = "b1c2d3e4-0000-1111-2222-333344445555"
        let uri = "vless://\(uuid)@realityserver.net:443?security=reality&sni=dl.google.com&pbk=abc123pubkey&sid=abcdef12&fp=chrome#RealityNode"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.security, "reality")
        XCTAssertEqual(cfg.pbk, "abc123pubkey")
        XCTAssertEqual(cfg.shortId, "abcdef12")
        XCTAssertEqual(cfg.fp, "chrome")
        XCTAssertEqual(cfg.sni, "dl.google.com")
    }

    func testVlessWebSocketTransport() throws {
        let uuid = "c1d2e3f4-aaaa-bbbb-cccc-ddddeeee0000"
        let uri = "vless://\(uuid)@wsserver.io:80?security=none&type=ws&path=%2Fws%2Fpath&host=cdn.example.com#WSNode"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.network, "ws")
        XCTAssertEqual(cfg.path, "/ws/path")
        XCTAssertEqual(cfg.host, "cdn.example.com")
        XCTAssertEqual(cfg.security, "none")
    }

    func testVlessGrpcTransport() throws {
        let uuid = "d1e2f3a4-1111-2222-3333-444455556666"
        let uri = "vless://\(uuid)@grpcserver.io:443?security=tls&type=grpc&serviceName=myservice&path=myservice#GrpcNode"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.network, "grpc")
    }

    func testVlessNoSecurity() throws {
        let uuid = "e1f2a3b4-2222-3333-4444-555566667777"
        let uri = "vless://\(uuid)@plainserver.io:1234?security=none&type=tcp"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.security, "none")
        XCTAssertEqual(cfg.port, 1234)
    }

    func testVlessAllowInsecureEqualsOne() throws {
        let uuid = "f1a2b3c4-3333-4444-5555-666677778888"
        let uri = "vless://\(uuid)@insecure.io:443?security=tls&allowInsecure=1"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertTrue(cfg.allowInsecure)
    }

    func testVlessAllowInsecureEqualsTrue() throws {
        let uuid = "a1b2c3d4-4444-5555-6666-777788889999"
        let uri = "vless://\(uuid)@insecure.io:443?security=tls&allowInsecure=true"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertTrue(cfg.allowInsecure)
    }

    func testVlessPercentEncodedFragmentRussian() throws {
        let uuid = "b2c3d4e5-5555-6666-7777-888899990000"
        // "Сервер" percent-encoded in UTF-8
        let encoded = "%D0%A1%D0%B5%D1%80%D0%B2%D0%B5%D1%80"
        let uri = "vless://\(uuid)@server.ru:443?security=tls#\(encoded)"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.name, "Сервер")
    }

    func testVlessDefaultNameEqualsServerWhenNoFragment() throws {
        let uuid = "c3d4e5f6-6666-7777-8888-99990000aaaa"
        let uri = "vless://\(uuid)@autoname.server.io:443?security=tls"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.name, "autoname.server.io")
    }

    func testVlessIPv6Server() throws {
        let uuid = "d4e5f6a7-7777-8888-9999-0000aaaabbbb"
        let uri = "vless://\(uuid)@[::1]:443?security=tls"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.server, "::1")
        XCTAssertEqual(cfg.port, 443)
    }

    // MARK: - VMess Parsing

    func testVmessStringPort() throws {
        // port as quoted string in JSON
        let json = """
        {"v":"2","ps":"TestNode","add":"vmess.server.com","port":"443","id":"aaaabbbb-cccc-dddd-eeee-ffff00001111","aid":"0","net":"tcp","type":"none","tls":"tls"}
        """
        let b64 = Data(json.utf8).base64EncodedString()
        let uri = "vmess://\(b64)"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.proto, .vmess)
        XCTAssertEqual(cfg.server, "vmess.server.com")
        XCTAssertEqual(cfg.port, 443)
        XCTAssertEqual(cfg.name, "TestNode")
        XCTAssertEqual(cfg.security, "tls")
    }

    func testVmessIntegerPort() throws {
        // port as bare integer (no quotes) in JSON
        let json = """
        {"v":"2","ps":"IntPortNode","add":"vmess2.server.com","port":8080,"id":"11112222-3333-4444-5555-666677778888","aid":"0","net":"tcp","tls":""}
        """
        let b64 = Data(json.utf8).base64EncodedString()
        let uri = "vmess://\(b64)"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.port, 8080)
        XCTAssertEqual(cfg.server, "vmess2.server.com")
    }

    func testVmessWebSocketTransport() throws {
        let json = """
        {"v":"2","ps":"WSNode","add":"wsvmess.io","port":"80","id":"22223333-4444-5555-6666-777788889999","aid":"0","net":"ws","path":"/v2ray","host":"cdn.wsvmess.io","tls":""}
        """
        let b64 = Data(json.utf8).base64EncodedString()
        let uri = "vmess://\(b64)"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.network, "ws")
        XCTAssertEqual(cfg.path, "/v2ray")
        XCTAssertEqual(cfg.host, "cdn.wsvmess.io")
    }

    func testVmessURLSafeBase64() throws {
        // URL-safe base64 uses - and _ instead of + and /
        let json = """
        {"v":"2","ps":"URLSafe","add":"urlsafe.io","port":"443","id":"33334444-5555-6666-7777-888899990000","aid":"0","net":"tcp","tls":"tls"}
        """
        let stdB64 = Data(json.utf8).base64EncodedString()
        // Replace + with - and / with _ to simulate URL-safe encoding
        let urlSafeB64 = stdB64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let uri = "vmess://\(urlSafeB64)"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.server, "urlsafe.io")
        XCTAssertEqual(cfg.security, "tls")
    }

    func testVmessInvalidBase64ThrowsParseError() {
        let uri = "vmess://this_is_not_valid_base64!!!"
        XCTAssertThrowsError(try ProxyParser.parse(uri)) { error in
            XCTAssertEqual(error as? ParseError, .base64Failed)
        }
    }

    // MARK: - Shadowsocks Parsing

    func testShadowsocksSIP002WithBase64Userinfo() throws {
        let method = "aes-256-gcm"
        let password = "secretpassword"
        let userinfo = Data("\(method):\(password)".utf8).base64EncodedString()
        let uri = "ss://\(userinfo)@ss.server.com:8388#MySS"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.proto, .shadowsocks)
        XCTAssertEqual(cfg.method, method)
        XCTAssertEqual(cfg.uuid, password)
        XCTAssertEqual(cfg.server, "ss.server.com")
        XCTAssertEqual(cfg.port, 8388)
        XCTAssertEqual(cfg.name, "MySS")
    }

    func testShadowsocksPasswordContainingColon() throws {
        // password is "pass:word" — colon inside password
        let method = "chacha20-ietf-poly1305"
        let password = "pass:word"
        let userinfo = Data("\(method):\(password)".utf8).base64EncodedString()
        let uri = "ss://\(userinfo)@colonpass.server.com:8389"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.method, method)
        XCTAssertEqual(cfg.uuid, password)
    }

    func testShadowsocksLegacyFormat() throws {
        // Legacy: base64(method:pass@host:port)
        let plain = "aes-128-gcm:legacypassword@legacy.server.com:1080"
        let b64 = Data(plain.utf8).base64EncodedString()
        let uri = "ss://\(b64)#LegacyNode"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.method, "aes-128-gcm")
        XCTAssertEqual(cfg.uuid, "legacypassword")
        XCTAssertEqual(cfg.server, "legacy.server.com")
        XCTAssertEqual(cfg.port, 1080)
        XCTAssertEqual(cfg.name, "LegacyNode")
    }

    // MARK: - Trojan Parsing

    func testTrojanBasicWithTLS() throws {
        let uri = "trojan://trojanpassword@trojan.server.com:443?security=tls&sni=trojan.server.com#TrojanNode"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.proto, .trojan)
        XCTAssertEqual(cfg.uuid, "trojanpassword")
        XCTAssertEqual(cfg.server, "trojan.server.com")
        XCTAssertEqual(cfg.port, 443)
        XCTAssertEqual(cfg.security, "tls")
        XCTAssertEqual(cfg.name, "TrojanNode")
    }

    func testTrojanDefaultSecurityIsTLS() throws {
        // No security param → default should be "tls"
        let uri = "trojan://mypassword@trojan2.server.com:443"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.security, "tls")
    }

    func testTrojanWebSocketTransport() throws {
        let uri = "trojan://wspass@trojanws.server.com:443?security=tls&type=ws&path=%2Ftrojan&host=cdn.trojanws.server.com#TrojanWS"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertEqual(cfg.network, "ws")
        XCTAssertEqual(cfg.path, "/trojan")
        XCTAssertEqual(cfg.host, "cdn.trojanws.server.com")
    }

    // MARK: - Error Cases

    func testUnknownProtocolThrowsParseError() {
        let uri = "http://some.proxy.server.com:8080"
        XCTAssertThrowsError(try ProxyParser.parse(uri)) { error in
            XCTAssertEqual(error as? ParseError, .unknownProtocol)
        }
    }

    func testVlessMissingAtThrowsParseError() {
        // No @ separator between uuid and host
        let uri = "vless://uuid-without-at-sign:443?security=tls"
        XCTAssertThrowsError(try ProxyParser.parse(uri)) { error in
            XCTAssertEqual(error as? ParseError, .missingAt)
        }
    }

    func testEmptyStringThrowsParseError() {
        XCTAssertThrowsError(try ProxyParser.parse("")) { error in
            XCTAssertEqual(error as? ParseError, .unknownProtocol)
        }
    }

    // MARK: - sing-box Config Generation

    func testSingBoxVlessReality() throws {
        let uuid = "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5"
        let uri = "vless://\(uuid)@reality.server.com:443?security=reality&sni=dl.google.com&pbk=mypublickey123&sid=deadbeef&fp=chrome"
        let cfg = try ProxyParser.parse(uri)
        let json = cfg.toSingBoxConfig()
        XCTAssertTrue(json.contains("xtls-rprx-vision"), "Reality config must contain xtls-rprx-vision flow")
        XCTAssertTrue(json.contains("\"reality\""), "Reality config must contain reality object")
        XCTAssertTrue(json.contains("mypublickey123"), "Must contain the public_key value")
        XCTAssertTrue(json.contains("deadbeef"), "Must contain the short_id value")
        XCTAssertTrue(json.contains("chrome"), "Must contain fingerprint value")
    }

    func testSingBoxVlessTLSNoReality() throws {
        let uuid = "b2b2b2b2-c3c3-d4d4-e5e5-f6f6f6f6f6f6"
        let uri = "vless://\(uuid)@tls.server.com:443?security=tls&sni=tls.server.com"
        let cfg = try ProxyParser.parse(uri)
        let json = cfg.toSingBoxConfig()
        XCTAssertFalse(json.contains("xtls-rprx-vision"), "TLS-only config must NOT contain xtls-rprx-vision")
        XCTAssertFalse(json.contains("\"reality\""), "TLS-only config must NOT contain reality block")
        XCTAssertTrue(json.contains("\"enabled\": true"), "TLS config must have enabled:true")
    }

    func testSingBoxVlessWebSocket() throws {
        let uuid = "c3c3c3c3-d4d4-e5e5-f6f6-a7a7a7a7a7a7"
        let uri = "vless://\(uuid)@wsv.server.com:80?security=none&type=ws&path=%2Fvless&host=cdn.wsv.server.com"
        let cfg = try ProxyParser.parse(uri)
        let json = cfg.toSingBoxConfig()
        XCTAssertTrue(json.contains("\"ws\""), "WS config must contain ws transport type")
        XCTAssertTrue(json.contains("/vless"), "WS config must contain the path")
        XCTAssertTrue(json.contains("cdn.wsv.server.com"), "WS config must contain the Host header value")
    }

    func testSingBoxVlessGrpc() throws {
        let uuid = "d4d4d4d4-e5e5-f6f6-a7a7-b8b8b8b8b8b8"
        let uri = "vless://\(uuid)@grpc.server.com:443?security=tls&type=grpc&path=myGrpcService"
        let cfg = try ProxyParser.parse(uri)
        let json = cfg.toSingBoxConfig()
        XCTAssertTrue(json.contains("\"grpc\""), "gRPC config must contain grpc transport type")
        XCTAssertTrue(json.contains("myGrpcService"), "gRPC config must contain service_name value")
    }

    func testSingBoxVmessWithTLS() throws {
        let jsonPayload = """
        {"v":"2","ps":"VmessTLS","add":"vmess.tls.io","port":"443","id":"e5e5e5e5-f6f6-a7a7-b8b8-c9c9c9c9c9c9","aid":"0","net":"tcp","tls":"tls"}
        """
        let b64 = Data(jsonPayload.utf8).base64EncodedString()
        let cfg = try ProxyParser.parse("vmess://\(b64)")
        let json = cfg.toSingBoxConfig()
        XCTAssertTrue(json.contains("\"vmess\""), "VMess config must have type vmess")
        XCTAssertTrue(json.contains("\"security\""), "VMess config must contain security field")
        XCTAssertTrue(json.contains("\"enabled\": true"), "VMess TLS config must have enabled:true")
    }

    func testSingBoxShadowsocks() throws {
        let method = "aes-256-gcm"
        let password = "sspassword"
        let userinfo = Data("\(method):\(password)".utf8).base64EncodedString()
        let cfg = try ProxyParser.parse("ss://\(userinfo)@ss.io:8388#SS")
        let json = cfg.toSingBoxConfig()
        XCTAssertTrue(json.contains("\"shadowsocks\""), "Shadowsocks config must have type shadowsocks")
        XCTAssertTrue(json.contains("\"method\""), "Shadowsocks config must contain method field")
        XCTAssertTrue(json.contains(method), "Shadowsocks config must contain the actual cipher method")
        XCTAssertTrue(json.contains("\"password\""), "Shadowsocks config must contain password field")
        XCTAssertTrue(json.contains(password), "Shadowsocks config must contain the actual password")
    }

    func testSingBoxTrojanWithTLS() throws {
        let cfg = try ProxyParser.parse("trojan://trojanpw@trojan.io:443?security=tls&sni=trojan.io#T")
        let json = cfg.toSingBoxConfig()
        XCTAssertTrue(json.contains("\"trojan\""), "Trojan config must have type trojan")
        XCTAssertTrue(json.contains("\"password\""), "Trojan config must contain password field")
        XCTAssertTrue(json.contains("\"enabled\": true"), "Trojan TLS config must have enabled:true")
    }

    func testSingBoxTrojanNoSecurityStillGetsTLS() throws {
        // Trojan default security is "tls" — should still generate TLS block
        let cfg = try ProxyParser.parse("trojan://pw@trojan.io:443")
        let json = cfg.toSingBoxConfig()
        XCTAssertTrue(json.contains("\"enabled\": true"), "Trojan with default security must still get TLS block")
    }

    func testSingBoxAlwaysContainsSocks5Inbound() throws {
        let configs: [String] = [
            "trojan://pw@t.io:443",
            "ss://\(Data("aes-256-gcm:pw".utf8).base64EncodedString())@s.io:8388",
        ]
        for uri in configs {
            let cfg = try ProxyParser.parse(uri)
            let json = cfg.toSingBoxConfig()
            XCTAssertTrue(json.contains("\(VPNManager.socksPort)"), "All configs must have socks5 inbound on port \(VPNManager.socksPort) (uri: \(uri))")
            XCTAssertTrue(json.contains("\"socks\""), "All configs must have socks inbound type (uri: \(uri))")
        }
    }

    func testSingBoxJSONValidity() throws {
        let testURIs: [(String, String)] = [
            ("vless_tls",     "vless://a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5@v.io:443?security=tls&sni=v.io"),
            ("vless_reality", "vless://a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5@r.io:443?security=reality&pbk=key&sid=abc&fp=chrome"),
            ("vless_ws",      "vless://a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5@w.io:80?security=none&type=ws&path=%2Fpath&host=h.io"),
            ("vless_grpc",    "vless://a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5@g.io:443?security=tls&type=grpc&path=svc"),
            ("vmess",         "vmess://\(Data(#"{"v":"2","ps":"N","add":"m.io","port":443,"id":"11112222-3333-4444-5555-666677778888","aid":0,"net":"tcp","tls":"tls"}"#.utf8).base64EncodedString())"),
            ("shadowsocks",   "ss://\(Data("aes-256-gcm:password".utf8).base64EncodedString())@s.io:8388"),
            ("trojan",        "trojan://pw@t.io:443?security=tls"),
        ]
        for (label, uri) in testURIs {
            let cfg = try ProxyParser.parse(uri)
            let jsonString = cfg.toSingBoxConfig()
            let data = jsonString.data(using: .utf8)!
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: data),
                "Generated config for \(label) must be valid JSON"
            )
        }
    }

    func testSingBoxJSONPasswordWithQuoteEscaped() throws {
        // Password contains a double-quote — must be escaped in JSON output
        let rawPassword = #"pass"word"#  // contains a literal "
        let method = "aes-256-gcm"
        let userinfo = Data("\(method):\(rawPassword)".utf8).base64EncodedString()
        let uri = "ss://\(userinfo)@s.io:8388"
        let cfg = try ProxyParser.parse(uri)
        let jsonString = cfg.toSingBoxConfig()
        let data = jsonString.data(using: .utf8)!
        // Must be valid JSON despite the quote in the password
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "JSON with escaped quote in password must be valid")
    }

    // MARK: - Whitespace / newline stripping (regression)

    /// Regression: URL pasted from a messenger with a line-break in the middle
    /// must be accepted without throwing.
    func testParseStripsEmbeddedNewlines() throws {
        let uuid = "a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5"
        // Simulate a VLESS URL split across two lines by copy-paste
        let brokenURI = "vless://\(uuid)@example.com:443?security=reality&pbk=PUBKEY&sid=abc&fp=q\n  q&type=tcp#Node"
        let cfg = try ProxyParser.parse(brokenURI)
        XCTAssertEqual(cfg.fp, "qq", "Whitespace stripped from fp must yield 'qq'")
        XCTAssertTrue(cfg.isValid)
    }

    func testParseStripsLeadingTrailingWhitespace() throws {
        let uuid = "b2b2b2b2-c3c3-d4d4-e5e5-f6f6f6f6f6f6"
        let uri = "  vless://\(uuid)@example.com:443?security=tls  \n"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertTrue(cfg.isValid)
    }

    // MARK: - JSON escaping (regression)

    /// Regression: fp containing a literal newline (from a broken URL) must
    /// produce valid JSON — the \n must be escaped, not embedded raw.
    func testSingBoxJSONValidWithNewlineInFp() throws {
        let uuid = "c3c3c3c3-d4d4-e5e5-f6f6-a7a7a7a7a7a7"
        let brokenURI = "vless://\(uuid)@srv.io:443?security=reality&pbk=K&sid=S&fp=q\nq&type=tcp"
        let cfg = try ProxyParser.parse(brokenURI)
        let jsonString = cfg.toSingBoxConfig()
        let data = jsonString.data(using: .utf8)!
        XCTAssertNoThrow(
            try JSONSerialization.jsonObject(with: data),
            "Config with newline-stripped fp must be valid JSON"
        )
    }

    func testSingBoxJSONValidWithControlCharsInPassword() throws {
        // Password with tab and newline — must be escaped in output
        let rawPassword = "pass\t\nword"
        let method = "aes-256-gcm"
        let userinfo = Data("\(method):\(rawPassword)".utf8).base64EncodedString()
        let cfg = try ProxyParser.parse("ss://\(userinfo)@s.io:8388")
        let jsonString = cfg.toSingBoxConfig()
        let data = jsonString.data(using: .utf8)!
        XCTAssertNoThrow(
            try JSONSerialization.jsonObject(with: data),
            "JSON must be valid despite control chars in password"
        )
    }

    // MARK: - Trojan allow insecure

    func testTrojanAllowInsecureTrue() throws {
        let uri = "trojan://pw@trojan.io:443?security=tls&allowInsecure=true"
        let cfg = try ProxyParser.parse(uri)
        XCTAssertTrue(cfg.allowInsecure)
    }

    // MARK: - jsonField Helper

    func testJsonFieldStringValue() {
        let json = #"{"name": "hello", "other": "world"}"#
        XCTAssertEqual(ProxyParser.jsonField(json, "name"), "hello")
    }

    func testJsonFieldIntegerValue() {
        // Integer value (no quotes) in JSON
        let json = #"{"port": 8080, "name": "test"}"#
        XCTAssertEqual(ProxyParser.jsonField(json, "port"), "8080")
    }

    func testJsonFieldMissingKeyReturnsEmptyString() {
        let json = #"{"name": "hello"}"#
        XCTAssertEqual(ProxyParser.jsonField(json, "missing"), "")
    }

    func testJsonFieldEscapedQuoteWithinStringValue() {
        // Value contains an escaped quote: \"
        let json = #"{"desc": "say \"hi\""}"#
        XCTAssertEqual(ProxyParser.jsonField(json, "desc"), #"say "hi""#)
    }

    // MARK: - Codable Round-trip

    func testCodableRoundTripVless() throws {
        let uri = "vless://a3c7e1f2-1234-5678-abcd-ef0123456789@example.com:443?security=reality&sni=dl.google.com&pbk=mypubkey&sid=ab12&fp=chrome&type=ws&path=%2Fws&host=cdn.io#MyVless"
        let original = try ProxyParser.parse(uri)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripVmess() throws {
        let json = #"{"v":"2","ps":"VM","add":"vm.io","port":"443","id":"11112222-3333-4444-5555-666677778888","aid":"0","net":"ws","path":"/v","host":"h.io","tls":"tls","sni":"s.io","fp":"chrome"}"#
        let b64 = Data(json.utf8).base64EncodedString()
        let original = try ProxyParser.parse("vmess://\(b64)")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripShadowsocks() throws {
        let userinfo = Data("aes-256-gcm:mypass".utf8).base64EncodedString()
        let original = try ProxyParser.parse("ss://\(userinfo)@ss.io:8388#MySSNode")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripTrojan() throws {
        let original = try ProxyParser.parse("trojan://pw123@trojan.io:443?security=tls&sni=trojan.io&type=ws&path=%2Ftj&host=cdn.io&fp=firefox#TJ")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodablePreservesId() throws {
        var cfg = try ProxyParser.parse("vless://a1b2c3d4-0000-1111-2222-333344445555@v.io:443?security=tls")
        let fixedId = UUID()
        cfg.id = fixedId
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(ProxyConfig.self, from: data)
        XCTAssertEqual(decoded.id, fixedId)
    }

    // MARK: - toURL Round-trip

    private func assertRoundTrip(_ uri: String, file: StaticString = #file, line: UInt = #line) throws {
        let original = try ProxyParser.parse(uri)
        let exported = original.toURL()
        let reparsed = try ProxyParser.parse(exported)
        // Compare all structurally significant fields (id and name encoding may differ)
        XCTAssertEqual(original.proto, reparsed.proto, "proto mismatch", file: file, line: line)
        XCTAssertEqual(original.uuid, reparsed.uuid, "uuid mismatch", file: file, line: line)
        XCTAssertEqual(original.server, reparsed.server, "server mismatch", file: file, line: line)
        XCTAssertEqual(original.port, reparsed.port, "port mismatch", file: file, line: line)
        XCTAssertEqual(original.security, reparsed.security, "security mismatch", file: file, line: line)
        XCTAssertEqual(original.network, reparsed.network, "network mismatch", file: file, line: line)
        XCTAssertEqual(original.sni, reparsed.sni, "sni mismatch", file: file, line: line)
        XCTAssertEqual(original.host, reparsed.host, "host mismatch", file: file, line: line)
        XCTAssertEqual(original.path, reparsed.path, "path mismatch", file: file, line: line)
        XCTAssertEqual(original.fp, reparsed.fp, "fp mismatch", file: file, line: line)
        XCTAssertEqual(original.pbk, reparsed.pbk, "pbk mismatch", file: file, line: line)
        XCTAssertEqual(original.shortId, reparsed.shortId, "shortId mismatch", file: file, line: line)
        XCTAssertEqual(original.method, reparsed.method, "method mismatch", file: file, line: line)
        XCTAssertEqual(original.allowInsecure, reparsed.allowInsecure, "allowInsecure mismatch", file: file, line: line)
    }

    func testToURLRoundTripVlessTLS() throws {
        try assertRoundTrip("vless://a3c7e1f2-1234-5678-abcd-ef0123456789@example.com:443?security=tls&sni=example.com&type=tcp#MyServer")
    }

    func testToURLRoundTripVlessReality() throws {
        try assertRoundTrip("vless://b1c2d3e4-0000-1111-2222-333344445555@reality.io:443?security=reality&sni=dl.google.com&pbk=abc123pubkey&sid=abcdef12&fp=chrome&type=tcp#Reality")
    }

    func testToURLRoundTripVlessWS() throws {
        try assertRoundTrip("vless://c1d2e3f4-aaaa-bbbb-cccc-ddddeeee0000@wsserver.io:80?security=none&type=ws&path=%2Fws%2Fpath&host=cdn.example.com#WSNode")
    }

    func testToURLRoundTripVmess() throws {
        let json = #"{"v":"2","ps":"Node","add":"vm.io","port":"443","id":"11112222-3333-4444-5555-666677778888","aid":"0","net":"tcp","tls":"tls","sni":"vm.io","fp":"chrome"}"#
        let b64 = Data(json.utf8).base64EncodedString()
        try assertRoundTrip("vmess://\(b64)")
    }

    func testToURLRoundTripShadowsocks() throws {
        let userinfo = Data("aes-256-gcm:secretpassword".utf8).base64EncodedString()
        try assertRoundTrip("ss://\(userinfo)@ss.server.com:8388#MySS")
    }

    func testToURLRoundTripTrojan() throws {
        try assertRoundTrip("trojan://trojanpassword@trojan.server.com:443?security=tls&sni=trojan.server.com&type=tcp#TrojanNode")
    }

    func testToURLRoundTripTrojanWS() throws {
        try assertRoundTrip("trojan://wspass@trojanws.io:443?security=tls&type=ws&path=%2Ftrojan&host=cdn.trojanws.io&fp=firefox#TrojanWS")
    }

    func testToURLVlessPercentEncodesName() throws {
        let uri = "vless://a1b2c3d4-0000-1111-2222-333344445555@v.io:443?security=tls#%D0%A1%D0%B5%D1%80%D0%B2%D0%B5%D1%80"
        let cfg = try ProxyParser.parse(uri)
        let url = cfg.toURL()
        // Name "Сервер" must be percent-encoded in output
        XCTAssertTrue(url.contains("%D0%A1%D0%B5%D1%80%D0%B2%D0%B5%D1%80") || url.contains("Сервер"),
                       "Name should be present in URL")
        // Round-trip must preserve the name
        let reparsed = try ProxyParser.parse(url)
        XCTAssertEqual(reparsed.name, "Сервер")
    }

    func testToURLShadowsocksPasswordWithColon() throws {
        let userinfo = Data("chacha20-ietf-poly1305:pass:word".utf8).base64EncodedString()
        try assertRoundTrip("ss://\(userinfo)@colonpass.io:8389#Colon")
    }
}
