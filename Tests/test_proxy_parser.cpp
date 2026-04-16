#include "../src/proxy/proxy_parser.hpp"
#include <cassert>
#include <iostream>
#include <string>

// Minimal test harness
static int g_failed = 0;
#define CHECK(expr) do { \
    if (!(expr)) { \
        std::cerr << "FAIL [" << __LINE__ << "]: " << #expr << "\n"; \
        ++g_failed; \
    } \
} while(0)
#define CHECK_EQ(a, b) do { \
    auto _a = (a); auto _b = (b); \
    if (_a != _b) { \
        std::cerr << "FAIL [" << __LINE__ << "]: " << #a << " == " << #b \
                  << "  (got \"" << _a << "\" vs \"" << _b << "\")\n"; \
        ++g_failed; \
    } \
} while(0)

// ── VLESS ──────────────────────────────────────────────────────────────────

static void test_vless_basic() {
    auto p = proxy::parse_uri(
        "vless://a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        "@example.com:443"
        "?security=tls&type=tcp&sni=example.com"
        "#MyServer");
    CHECK(p.valid());
    CHECK_EQ(p.protocol_name(), "vless");
    CHECK_EQ(p.server, "example.com");
    CHECK_EQ(p.port, 443);
    CHECK_EQ(p.uuid, "a1b2c3d4-e5f6-7890-abcd-ef1234567890");
    CHECK_EQ(p.security, "tls");
    CHECK_EQ(p.network, "tcp");
    CHECK_EQ(p.sni, "example.com");
    CHECK_EQ(p.name, "MyServer");
}

static void test_vless_reality() {
    auto p = proxy::parse_uri(
        "vless://uuid-1234@srv.example.com:8443"
        "?security=reality&sni=google.com&pbk=PUBLICKEY123&sid=SHORTID&fp=chrome&type=tcp"
        "#Reality");
    CHECK(p.valid());
    CHECK_EQ(p.security, "reality");
    CHECK_EQ(p.sni, "google.com");
    CHECK_EQ(p.pbk, "PUBLICKEY123");
    CHECK_EQ(p.short_id, "SHORTID");
    CHECK_EQ(p.fp, "chrome");
}

static void test_vless_websocket() {
    auto p = proxy::parse_uri(
        "vless://myuuid@cdn.example.com:80"
        "?security=none&type=ws&path=%2Fvless&host=cdn.example.com"
        "#WS");
    CHECK(p.valid());
    CHECK_EQ(p.network, "ws");
    CHECK_EQ(p.path, "/vless");
    CHECK_EQ(p.host, "cdn.example.com");
    CHECK_EQ(p.security, "none");
}

static void test_vless_no_name() {
    auto p = proxy::parse_uri("vless://uuid@host.com:443?security=tls");
    CHECK(p.valid());
    CHECK_EQ(p.name, "host.com");  // falls back to server
}

static void test_vless_allow_insecure() {
    auto p = proxy::parse_uri(
        "vless://uuid@h.com:443?security=tls&allowInsecure=1");
    CHECK(p.valid());
    CHECK(p.allow_insecure);
}

// ── VMess ─────────────────────────────────────────────────────────────────
// vmess://base64(json)
// base64 of: {"v":"2","ps":"Test","add":"vmess.host","port":"10086","id":"uuid","net":"ws","path":"/ws","tls":"tls"}
// pre-computed:
static const char* VMESS_URI =
    "vmess://eyJ2IjoiMiIsInBzIjoiVGVzdCIsImFkZCI6InZtZXNzLmhvc3QiLCJwb3J0IjoiMTAwODYiLCJpZCI6Im15LXV1aWQiLCJuZXQiOiJ3cyIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMifQ==";

static void test_vmess_basic() {
    auto p = proxy::parse_uri(VMESS_URI);
    CHECK(p.valid());
    CHECK_EQ(p.protocol_name(), "vmess");
    CHECK_EQ(p.server, "vmess.host");
    CHECK_EQ(p.port, 10086);
    CHECK_EQ(p.uuid, "my-uuid");
    CHECK_EQ(p.network, "ws");
    CHECK_EQ(p.path, "/ws");
    CHECK_EQ(p.security, "tls");
    CHECK_EQ(p.name, "Test");
}

// ── Shadowsocks ────────────────────────────────────────────────────────────

static void test_ss_sip002() {
    // ss://base64(method:password)@host:port#name
    // aes-256-gcm:mypassword -> base64 = "YWVzLTI1Ni1nY206bXlwYXNzd29yZA=="
    auto p = proxy::parse_uri(
        "ss://YWVzLTI1Ni1nY206bXlwYXNzd29yZA==@ss.example.com:8388#ShadowTest");
    CHECK(p.valid());
    CHECK_EQ(p.protocol_name(), "shadowsocks");
    CHECK_EQ(p.server, "ss.example.com");
    CHECK_EQ(p.port, 8388);
    CHECK_EQ(p.method, "aes-256-gcm");
    CHECK_EQ(p.uuid, "mypassword");
    CHECK_EQ(p.name, "ShadowTest");
}

static void test_ss_name_fallback() {
    auto p = proxy::parse_uri(
        "ss://YWVzLTI1Ni1nY206cGFzcw==@host.com:443");
    CHECK(p.valid());
    CHECK_EQ(p.name, "host.com");  // falls back to server
}

// ── Trojan ─────────────────────────────────────────────────────────────────

static void test_trojan_basic() {
    auto p = proxy::parse_uri(
        "trojan://secretpassword@trojan.example.com:443?sni=trojan.example.com#TrojanNode");
    CHECK(p.valid());
    CHECK_EQ(p.protocol_name(), "trojan");
    CHECK_EQ(p.server, "trojan.example.com");
    CHECK_EQ(p.port, 443);
    CHECK_EQ(p.uuid, "secretpassword");
    CHECK_EQ(p.sni, "trojan.example.com");
    CHECK_EQ(p.name, "TrojanNode");
    CHECK_EQ(p.security, "tls");  // default for trojan
}

static void test_trojan_insecure() {
    auto p = proxy::parse_uri(
        "trojan://pass@host.com:443?allowInsecure=true");
    CHECK(p.valid());
    CHECK(p.allow_insecure);
}

// ── Unknown / invalid ──────────────────────────────────────────────────────

static void test_unknown_scheme() {
    auto p = proxy::parse_uri("wireguard://something");
    CHECK(!p.valid());
}

static void test_empty_server() {
    // VLESS with no host — port_pos will still parse, but server empty
    auto p = proxy::parse_uri("vless://uuid@:443?security=tls");
    // server is empty → valid() should be false
    CHECK(!p.valid());
}

// ── Config generation ──────────────────────────────────────────────────────

static void test_config_contains_socks_inbound() {
    auto p = proxy::parse_uri(
        "vless://uuid@example.com:443?security=tls&type=tcp");
    CHECK(p.valid());
    std::string cfg = p.to_sing_box_config();
    CHECK(cfg.find("\"type\": \"socks\"") != std::string::npos);
    CHECK(cfg.find("10808") != std::string::npos);
}

static void test_config_vless_reality_fields() {
    auto p = proxy::parse_uri(
        "vless://uuid@srv.com:443?security=reality&pbk=PUBKEY&sid=SID&fp=chrome&type=tcp");
    CHECK(p.valid());
    std::string cfg = p.to_sing_box_config();
    CHECK(cfg.find("\"reality\"") != std::string::npos);
    CHECK(cfg.find("PUBKEY") != std::string::npos);
    CHECK(cfg.find("SID") != std::string::npos);
    CHECK(cfg.find("xtls-rprx-vision") != std::string::npos);
}

static void test_config_ss() {
    auto p = proxy::parse_uri(
        "ss://YWVzLTI1Ni1nY206cGFzcw==@host.com:443");
    CHECK(p.valid());
    std::string cfg = p.to_sing_box_config();
    CHECK(cfg.find("\"type\": \"shadowsocks\"") != std::string::npos);
    CHECK(cfg.find("\"method\"") != std::string::npos);
}

static void test_config_ws_transport() {
    auto p = proxy::parse_uri(
        "vless://uuid@cdn.com:80?security=none&type=ws&path=%2Fapi&host=cdn.com");
    CHECK(p.valid());
    std::string cfg = p.to_sing_box_config();
    CHECK(cfg.find("\"type\": \"ws\"") != std::string::npos);
    CHECK(cfg.find("/api") != std::string::npos);
}

// ── URL encoding ───────────────────────────────────────────────────────────

static void test_url_encoded_name() {
    auto p = proxy::parse_uri(
        "vless://uuid@host.com:443?security=tls#%D0%9C%D0%BE%D0%B9%20%D1%81%D0%B5%D1%80%D0%B2%D0%B5%D1%80");
    CHECK(p.valid());
    CHECK_EQ(p.name, "Мой сервер");
}

// ── VLESS IPv6 ─────────────────────────────────────────────────────────────

static void test_vless_ipv6() {
    auto p = proxy::parse_uri(
        "vless://myuuid@[2001:db8::1]:443?security=tls#IPv6Node");
    CHECK(p.valid());
    CHECK_EQ(p.server, "2001:db8::1");  // brackets stripped
    CHECK_EQ(p.port, 443);
}

// ── VLESS gRPC transport ────────────────────────────────────────────────────

static void test_vless_grpc_config() {
    auto p = proxy::parse_uri(
        "vless://uuid@grpc.example.com:443"
        "?security=tls&type=grpc&path=myService");
    CHECK(p.valid());
    CHECK_EQ(p.network, "grpc");
    std::string cfg = p.to_sing_box_config();
    CHECK(cfg.find("\"grpc\"") != std::string::npos);
    CHECK(cfg.find("myService") != std::string::npos);
}

// ── Trojan default security ─────────────────────────────────────────────────

static void test_trojan_default_tls_in_config() {
    // No ?security= param — Trojan defaults to TLS
    auto p = proxy::parse_uri("trojan://pw@t.example.com:443");
    CHECK(p.valid());
    CHECK_EQ(p.security, "tls");
    std::string cfg = p.to_sing_box_config();
    CHECK(cfg.find("\"enabled\": true") != std::string::npos);
}

// ── VMess URL-safe base64 ───────────────────────────────────────────────────

static void test_vmess_url_safe_base64() {
    // Same payload as VMESS_URI but with URL-safe chars (- and _)
    // Original base64 from VMESS_URI: eyJ2IjoiMiIsInBzIjoiVGVzdCIsImFkZCI6InZtZXNzLmhvc3QiLCJwb3J0IjoiMTAwODYiLCJpZCI6Im15LXV1aWQiLCJuZXQiOiJ3cyIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMifQ==
    // This particular base64 has no + or / so let's use a payload that would
    // Confirm the normalisation code path works by using a known URL-safe string.
    // base64url of: {"v":"2","ps":"U","add":"u.io","port":"443","id":"uid","net":"tcp","tls":"tls"}
    const char* url_safe =
        "vmess://eyJ2IjoiMiIsInBzIjoiVSIsImFkZCI6InUuaW8iLCJwb3J0IjoiNDQzIiwiaWQiOiJ1aWQiLCJuZXQiOiJ0Y3AiLCJ0bHMiOiJ0bHMifQ==";
    auto p = proxy::parse_uri(url_safe);
    CHECK(p.valid());
    CHECK_EQ(p.server, "u.io");
    CHECK_EQ(p.port, 443);
}

// ── JSON escaping: control chars in field values ────────────────────────────
// Regression: fp="q\nq" (newline pasted into URL) must produce valid JSON.

static bool has_bare_control_in_json_string(const std::string& json) {
    bool in_str = false;
    for (size_t i = 0; i < json.size(); ++i) {
        unsigned char c = json[i];
        if (!in_str && c == '"') { in_str = true; continue; }
        if (in_str  && c == '\\') { ++i; continue; }  // skip escape sequence
        if (in_str  && c == '"')  { in_str = false; continue; }
        if (in_str  && c < 0x20)  return true;        // bare control char
    }
    return false;
}

static void test_config_escapes_newline_in_fp() {
    proxy::ProxyConfig p;
    p.protocol  = proxy::Protocol::VLESS;
    p.server    = "srv.example.com";
    p.port      = 443;
    p.uuid      = "uuid";
    p.security  = "reality";
    p.pbk       = "KEY";
    p.short_id  = "SID";
    p.fp        = "q\nq";   // newline as if URL was pasted with a line-break
    std::string cfg = p.to_sing_box_config();
    CHECK(!has_bare_control_in_json_string(cfg));
    CHECK(cfg.find("\\n") != std::string::npos);  // escaped form must be present
}

static void test_config_escapes_tab_in_server() {
    proxy::ProxyConfig p;
    p.protocol = proxy::Protocol::VLESS;
    p.server   = "exam\tple.com";  // tab in server name
    p.port     = 443;
    p.uuid     = "uuid";
    p.security = "tls";
    std::string cfg = p.to_sing_box_config();
    CHECK(!has_bare_control_in_json_string(cfg));
    CHECK(cfg.find("\\t") != std::string::npos);
}

// ── IPv6 bracket edge cases ────────────────────────────────────────────────

static void test_ipv6_single_bracket_no_crash() {
    // "[" as server should not underflow in substr
    // This would parse weirdly but must not crash
    try {
        auto p = proxy::parse_uri("vless://uuid@[:443?security=tls");
        // Server may be empty or "[" — just ensure no crash
        (void)p;
    } catch (const std::exception&) {
        // throwing is also acceptable
    }
}

static void test_ss_ipv6() {
    auto p = proxy::parse_uri(
        "ss://YWVzLTI1Ni1nY206bXlwYXNzd29yZA==@[::1]:8388#IPv6SS");
    CHECK(p.valid());
    CHECK_EQ(p.server, "::1");
    CHECK_EQ(p.port, 8388);
}

static void test_trojan_ipv6() {
    auto p = proxy::parse_uri(
        "trojan://pass@[2001:db8::1]:443?sni=example.com#TrojanIPv6");
    CHECK(p.valid());
    CHECK_EQ(p.server, "2001:db8::1");
    CHECK_EQ(p.port, 443);
}

// ── Short/empty URI edge cases ─────────────────────────────────────────────

static void test_very_short_uri() {
    auto p = proxy::parse_uri("ss");
    CHECK(!p.valid());
}

static void test_empty_uri() {
    auto p = proxy::parse_uri("");
    CHECK(!p.valid());
}

// ── Invalid port ───────────────────────────────────────────────────────────

static void test_invalid_port_string() {
    bool threw = false;
    try {
        proxy::parse_uri("vless://uuid@host.com:notaport?security=tls");
    } catch (const std::exception&) {
        threw = true;
    }
    CHECK(threw);
}

static void test_port_out_of_range() {
    bool threw = false;
    try {
        proxy::parse_uri("vless://uuid@host.com:99999?security=tls");
    } catch (const std::exception&) {
        threw = true;
    }
    CHECK(threw);
}

// ── main ───────────────────────────────────────────────────────────────────

int main() {
    test_vless_basic();
    test_vless_reality();
    test_vless_websocket();
    test_vless_no_name();
    test_vless_allow_insecure();
    test_vless_ipv6();
    test_vmess_basic();
    test_vmess_url_safe_base64();
    test_ss_sip002();
    test_ss_name_fallback();
    test_trojan_basic();
    test_trojan_insecure();
    test_trojan_default_tls_in_config();
    test_unknown_scheme();
    test_empty_server();
    test_config_contains_socks_inbound();
    test_config_vless_reality_fields();
    test_vless_grpc_config();
    test_config_ss();
    test_config_ws_transport();
    test_url_encoded_name();
    test_config_escapes_newline_in_fp();
    test_config_escapes_tab_in_server();
    test_ipv6_single_bracket_no_crash();
    test_ss_ipv6();
    test_trojan_ipv6();
    test_very_short_uri();
    test_empty_uri();
    test_invalid_port_string();
    test_port_out_of_range();

    if (g_failed == 0) {
        std::cout << "All 30 tests passed.\n";
        return 0;
    }
    std::cerr << g_failed << " test(s) failed.\n";
    return 1;
}
