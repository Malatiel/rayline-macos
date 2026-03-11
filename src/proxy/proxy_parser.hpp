#pragma once
#include <string>
#include <cstdint>
#include <sstream>

namespace proxy {

enum class Protocol { VLESS, VMESS, SHADOWSOCKS, TROJAN, UNKNOWN };

struct ProxyConfig {
    Protocol    protocol    = Protocol::UNKNOWN;
    std::string name;
    std::string uuid;           // or password for trojan/ss
    std::string server;
    uint16_t    port        = 443;
    std::string encryption; // none, auto, aes-128-gcm, etc.
    std::string security;   // tls, reality, none
    std::string network;    // tcp, ws, grpc, h2
    std::string sni;
    std::string host;       // HTTP Host header (for WS)
    std::string path;       // WebSocket/HTTP path
    std::string short_id;   // for REALITY
    std::string fp;         // fingerprint
    std::string method;     // for shadowsocks: cipher method
    std::string pbk;        // REALITY public key
    bool        allow_insecure = false;

    // Convert to sing-box JSON config string
    std::string to_sing_box_config() const;

    bool valid() const { return protocol != Protocol::UNKNOWN && !server.empty(); }

    // Human-readable protocol name
    std::string protocol_name() const {
        switch (protocol) {
            case Protocol::VLESS:       return "vless";
            case Protocol::VMESS:       return "vmess";
            case Protocol::SHADOWSOCKS: return "shadowsocks";
            case Protocol::TROJAN:      return "trojan";
            default:                    return "unknown";
        }
    }
};

// Parse any of: vless://, vmess://, ss://, trojan://
ProxyConfig parse_uri(const std::string& uri);

} // namespace proxy
