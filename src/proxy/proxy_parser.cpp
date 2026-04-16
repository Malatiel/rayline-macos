#include "proxy_parser.hpp"
#include "../crypto/crypto.hpp"
#include <sstream>
#include <stdexcept>
#include <cctype>
#include <map>

namespace proxy {

// ---- URL helpers ----

static std::string url_decode(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%' && i + 2 < s.size()) {
            char h1 = s[i+1], h2 = s[i+2];
            auto hex = [](char c) -> int {
                if (c >= '0' && c <= '9') return c - '0';
                if (c >= 'a' && c <= 'f') return c - 'a' + 10;
                if (c >= 'A' && c <= 'F') return c - 'A' + 10;
                return -1;
            };
            int hi = hex(h1), lo = hex(h2);
            if (hi >= 0 && lo >= 0) {
                out += (char)((hi << 4) | lo);
                i += 2;
                continue;
            }
        } else if (s[i] == '+') {
            out += ' ';
            continue;
        }
        out += s[i];
    }
    return out;
}

static std::map<std::string, std::string> parse_query(const std::string& qs) {
    std::map<std::string, std::string> result;
    std::string key, val;
    bool inval = false;
    auto flush = [&]() {
        if (!key.empty()) {
            result[url_decode(key)] = url_decode(val);
        }
        key.clear(); val.clear(); inval = false;
    };
    for (char c : qs) {
        if (c == '&') { flush(); }
        else if (c == '=') { inval = true; }
        else if (inval) { val += c; }
        else { key += c; }
    }
    flush();
    return result;
}

// Base64 decode (standard and URL-safe variants)
static std::string base64_decode_str(const std::string& s) {
    // Normalize URL-safe base64 to standard
    std::string norm = s;
    for (char& c : norm) {
        if (c == '-') c = '+';
        if (c == '_') c = '/';
    }
    // Add padding
    while (norm.size() % 4 != 0) norm += '=';
    auto bytes = crypto::base64_decode(norm);
    return std::string(bytes.begin(), bytes.end());
}

static uint16_t parse_port(const std::string& s) {
    if (s.empty()) throw std::runtime_error("missing port");
    int p;
    try {
        p = std::stoi(s);
    } catch (const std::exception&) {
        throw std::runtime_error("invalid port: " + s);
    }
    if (p < 1 || p > 65535) throw std::runtime_error("port out of range: " + s);
    return static_cast<uint16_t>(p);
}

// ---- VLESS parser ----
// vless://uuid@host:port?params#name
static ProxyConfig parse_vless(const std::string& uri) {
    ProxyConfig cfg;
    cfg.protocol = Protocol::VLESS;

    // Strip scheme
    std::string rest = uri.substr(8); // after "vless://"

    // Fragment (name)
    auto hash_pos = rest.find('#');
    if (hash_pos != std::string::npos) {
        cfg.name = url_decode(rest.substr(hash_pos + 1));
        rest = rest.substr(0, hash_pos);
    }

    // Query string
    auto q_pos = rest.find('?');
    std::map<std::string, std::string> params;
    if (q_pos != std::string::npos) {
        params = parse_query(rest.substr(q_pos + 1));
        rest = rest.substr(0, q_pos);
    }

    // uuid@host:port
    auto at_pos = rest.find('@');
    if (at_pos == std::string::npos) throw std::runtime_error("VLESS URI: missing @");
    cfg.uuid = rest.substr(0, at_pos);
    std::string hostport = rest.substr(at_pos + 1);

    // host:port (handle IPv6 [::1]:port)
    auto port_pos = hostport.rfind(':');
    if (port_pos != std::string::npos) {
        cfg.server = hostport.substr(0, port_pos);
        // strip brackets for IPv6
        if (cfg.server.size() >= 2 && cfg.server.front() == '[' && cfg.server.back() == ']') {
            cfg.server = cfg.server.substr(1, cfg.server.size() - 2);
        }
        cfg.port = parse_port(hostport.substr(port_pos + 1));
    } else {
        cfg.server = hostport;
    }

    // Apply params
    auto get = [&](const std::string& k, const std::string& def = "") -> std::string {
        auto it = params.find(k);
        return it != params.end() ? it->second : def;
    };

    cfg.encryption = get("encryption", "none");
    cfg.security   = get("security", "none");
    cfg.network    = get("type", "tcp");
    cfg.sni        = get("sni");
    cfg.host       = get("host");
    cfg.path       = get("path", "/");
    cfg.fp         = get("fp");
    cfg.pbk        = get("pbk");
    cfg.short_id   = get("sid");
    cfg.allow_insecure = (get("allowInsecure") == "1" || get("allowInsecure") == "true");

    if (cfg.name.empty()) cfg.name = cfg.server;
    return cfg;
}

// ---- VMess parser ----
// vmess://base64(json)
static ProxyConfig parse_vmess(const std::string& uri) {
    ProxyConfig cfg;
    cfg.protocol = Protocol::VMESS;

    std::string b64 = uri.substr(8); // after "vmess://"
    // strip fragment
    auto hash_pos = b64.find('#');
    if (hash_pos != std::string::npos) {
        cfg.name = url_decode(b64.substr(hash_pos + 1));
        b64 = b64.substr(0, hash_pos);
    }

    std::string json_str;
    try {
        json_str = base64_decode_str(b64);
    } catch (...) {
        throw std::runtime_error("VMess URI: base64 decode failed");
    }

    // Minimal JSON parse for vmess config keys
    auto get_json_string = [&](const std::string& key) -> std::string {
        // look for "key":"value"
        std::string pat = "\"" + key + "\"";
        auto pos = json_str.find(pat);
        if (pos == std::string::npos) return "";
        pos += pat.size();
        // skip whitespace and colon
        while (pos < json_str.size() && (json_str[pos] == ' ' || json_str[pos] == ':')) ++pos;
        if (pos >= json_str.size()) return "";
        if (json_str[pos] == '"') {
            ++pos;
            std::string val;
            while (pos < json_str.size() && json_str[pos] != '"') {
                if (json_str[pos] == '\\' && pos + 1 < json_str.size()) {
                    ++pos; // skip escape
                }
                val += json_str[pos++];
            }
            return val;
        } else {
            // number
            std::string val;
            while (pos < json_str.size() && json_str[pos] != ',' && json_str[pos] != '}') {
                val += json_str[pos++];
            }
            // trim
            while (!val.empty() && std::isspace((unsigned char)val.back())) val.pop_back();
            return val;
        }
    };

    cfg.uuid    = get_json_string("id");
    cfg.server  = get_json_string("add");
    std::string port_str = get_json_string("port");
    if (!port_str.empty()) cfg.port = parse_port(port_str);
    cfg.network    = get_json_string("net");
    cfg.path       = get_json_string("path");
    cfg.host       = get_json_string("host");
    cfg.sni        = get_json_string("sni");
    cfg.security   = get_json_string("tls");
    cfg.fp         = get_json_string("fp");
    std::string ps = get_json_string("ps");
    if (cfg.name.empty()) cfg.name = ps;
    if (cfg.name.empty()) cfg.name = cfg.server;
    if (cfg.network.empty()) cfg.network = "tcp";
    cfg.encryption = "auto";

    return cfg;
}

// ---- Shadowsocks parser ----
// ss://base64(method:password)@host:port#name  OR
// ss://base64(method:password@host:port)#name
static ProxyConfig parse_ss(const std::string& uri) {
    ProxyConfig cfg;
    cfg.protocol = Protocol::SHADOWSOCKS;

    std::string rest = uri.substr(5); // after "ss://"

    // Fragment
    auto hash_pos = rest.find('#');
    if (hash_pos != std::string::npos) {
        cfg.name = url_decode(rest.substr(hash_pos + 1));
        rest = rest.substr(0, hash_pos);
    }

    // Check for SIP002 format: ss://userinfo@host:port
    // userinfo = base64(method:password) OR percent-encoded method:password
    std::string userinfo, hostport;
    auto at_pos = rest.find('@');
    if (at_pos != std::string::npos) {
        // SIP002
        userinfo = rest.substr(0, at_pos);
        hostport = rest.substr(at_pos + 1);

        // Decode userinfo
        std::string decoded;
        try {
            decoded = base64_decode_str(userinfo);
        } catch (...) {
            decoded = url_decode(userinfo);
        }

        auto colon = decoded.find(':');
        if (colon != std::string::npos) {
            cfg.method = decoded.substr(0, colon);
            cfg.uuid   = decoded.substr(colon + 1);
        } else {
            cfg.uuid = decoded;
        }
    } else {
        // Legacy: ss://base64(method:password@host:port)
        std::string decoded;
        try {
            decoded = base64_decode_str(rest);
        } catch (...) {
            decoded = rest;
        }
        // method:password@host:port
        auto at2 = decoded.rfind('@');
        if (at2 != std::string::npos) {
            userinfo = decoded.substr(0, at2);
            hostport = decoded.substr(at2 + 1);
            auto colon = userinfo.find(':');
            if (colon != std::string::npos) {
                cfg.method = userinfo.substr(0, colon);
                cfg.uuid   = userinfo.substr(colon + 1);
            } else {
                cfg.uuid = userinfo;
            }
        } else {
            hostport = decoded;
        }
    }

    // Parse host:port
    // Query string (SIP002 plugins etc.)
    auto q_pos = hostport.find('?');
    if (q_pos != std::string::npos) {
        hostport = hostport.substr(0, q_pos);
    }

    auto port_pos = hostport.rfind(':');
    if (port_pos != std::string::npos) {
        cfg.server = hostport.substr(0, port_pos);
        if (cfg.server.size() >= 2 && cfg.server.front() == '[' && cfg.server.back() == ']')
            cfg.server = cfg.server.substr(1, cfg.server.size() - 2);
        cfg.port = parse_port(hostport.substr(port_pos + 1));
    } else {
        cfg.server = hostport;
    }

    cfg.security = "none";
    cfg.network  = "tcp";
    if (cfg.name.empty()) cfg.name = cfg.server;
    return cfg;
}

// ---- Trojan parser ----
// trojan://password@host:port?params#name
static ProxyConfig parse_trojan(const std::string& uri) {
    ProxyConfig cfg;
    cfg.protocol = Protocol::TROJAN;

    std::string rest = uri.substr(9); // after "trojan://"

    auto hash_pos = rest.find('#');
    if (hash_pos != std::string::npos) {
        cfg.name = url_decode(rest.substr(hash_pos + 1));
        rest = rest.substr(0, hash_pos);
    }

    auto q_pos = rest.find('?');
    std::map<std::string, std::string> params;
    if (q_pos != std::string::npos) {
        params = parse_query(rest.substr(q_pos + 1));
        rest = rest.substr(0, q_pos);
    }

    auto at_pos = rest.find('@');
    if (at_pos == std::string::npos) throw std::runtime_error("Trojan URI: missing @");
    cfg.uuid = url_decode(rest.substr(0, at_pos));
    std::string hostport = rest.substr(at_pos + 1);

    auto port_pos = hostport.rfind(':');
    if (port_pos != std::string::npos) {
        cfg.server = hostport.substr(0, port_pos);
        if (cfg.server.size() >= 2 && cfg.server.front() == '[' && cfg.server.back() == ']')
            cfg.server = cfg.server.substr(1, cfg.server.size() - 2);
        cfg.port = parse_port(hostport.substr(port_pos + 1));
    } else {
        cfg.server = hostport;
    }

    auto get = [&](const std::string& k, const std::string& def = "") -> std::string {
        auto it = params.find(k);
        return it != params.end() ? it->second : def;
    };

    cfg.security = get("security", "tls");
    cfg.sni      = get("sni");
    cfg.network  = get("type", "tcp");
    cfg.path     = get("path", "/");
    cfg.host     = get("host");
    cfg.fp       = get("fp");
    cfg.allow_insecure = (get("allowInsecure") == "1" || get("allowInsecure") == "true");
    if (cfg.name.empty()) cfg.name = cfg.server;
    return cfg;
}

// ---- Public API ----

ProxyConfig parse_uri(const std::string& uri) {
    if (uri.compare(0, 8, "vless://")  == 0) return parse_vless(uri);
    if (uri.compare(0, 8, "vmess://")  == 0) return parse_vmess(uri);
    if (uri.compare(0, 5, "ss://")     == 0) return parse_ss(uri);
    if (uri.compare(0, 9, "trojan://") == 0) return parse_trojan(uri);

    ProxyConfig cfg;
    cfg.protocol = Protocol::UNKNOWN;
    return cfg;
}

// ---- sing-box JSON config generation ----

static std::string esc(const std::string& s) {
    std::string out;
    for (unsigned char c : s) {
        if      (c == '"')  out += "\\\"";
        else if (c == '\\') out += "\\\\";
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else if (c == '\t') out += "\\t";
        else if (c < 0x20) {
            char buf[8];
            std::snprintf(buf, sizeof(buf), "\\u%04x", c);
            out += buf;
        }
        else out += (char)c;
    }
    return out;
}

std::string ProxyConfig::to_sing_box_config() const {
    // Build sing-box JSON config
    std::ostringstream j;

    j << "{\n";
    j << "  \"log\": {\"level\": \"warn\"},\n";

    // Inbounds: SOCKS5 on 127.0.0.1:10808
    j << "  \"inbounds\": [\n";
    j << "    {\n";
    j << "      \"type\": \"socks\",\n";
    j << "      \"listen\": \"127.0.0.1\",\n";
    j << "      \"listen_port\": 10808,\n";
    j << "      \"sniff\": true,\n";
    j << "      \"sniff_override_destination\": true\n";
    j << "    }\n";
    j << "  ],\n";

    // Outbounds
    j << "  \"outbounds\": [\n";
    j << "    {\n";

    if (protocol == Protocol::VLESS) {
        j << "      \"type\": \"vless\",\n";
        j << "      \"server\": \"" << esc(server) << "\",\n";
        j << "      \"server_port\": " << port << ",\n";
        j << "      \"uuid\": \"" << esc(uuid) << "\"";

        bool use_reality = (security == "reality");
        bool use_tls     = (security == "tls" || use_reality);

        if (use_reality) {
            j << ",\n      \"flow\": \"xtls-rprx-vision\"";
        }

        if (use_tls) {
            j << ",\n      \"tls\": {\n";
            j << "        \"enabled\": true,\n";
            j << "        \"server_name\": \"" << esc(sni.empty() ? server : sni) << "\"";
            if (allow_insecure) {
                j << ",\n        \"insecure\": true";
            }
            if (!fp.empty()) {
                j << ",\n        \"utls\": {\n";
                j << "          \"enabled\": true,\n";
                j << "          \"fingerprint\": \"" << esc(fp) << "\"\n";
                j << "        }";
            }
            if (use_reality) {
                j << ",\n        \"reality\": {\n";
                j << "          \"enabled\": true,\n";
                j << "          \"public_key\": \"" << esc(pbk) << "\",\n";
                j << "          \"short_id\": \"" << esc(short_id) << "\"\n";
                j << "        }";
            }
            j << "\n      }";
        }

        // Transport
        if (network == "ws") {
            j << ",\n      \"transport\": {\n";
            j << "        \"type\": \"ws\",\n";
            j << "        \"path\": \"" << esc(path.empty() ? "/" : path) << "\"";
            if (!host.empty()) {
                j << ",\n        \"headers\": {\"Host\": \"" << esc(host) << "\"}";
            }
            j << "\n      }";
        } else if (network == "grpc") {
            j << ",\n      \"transport\": {\n";
            j << "        \"type\": \"grpc\",\n";
            j << "        \"service_name\": \"" << esc(path) << "\"\n";
            j << "      }";
        } else if (network == "h2") {
            j << ",\n      \"transport\": {\n";
            j << "        \"type\": \"http\",\n";
            j << "        \"path\": \"" << esc(path.empty() ? "/" : path) << "\"";
            if (!host.empty()) {
                j << ",\n        \"host\": [\"" << esc(host) << "\"]";
            }
            j << "\n      }";
        }
        j << "\n    }\n";

    } else if (protocol == Protocol::VMESS) {
        j << "      \"type\": \"vmess\",\n";
        j << "      \"server\": \"" << esc(server) << "\",\n";
        j << "      \"server_port\": " << port << ",\n";
        j << "      \"uuid\": \"" << esc(uuid) << "\",\n";
        j << "      \"security\": \"" << esc(encryption.empty() ? "auto" : encryption) << "\"";

        bool use_tls = (security == "tls");
        if (use_tls) {
            j << ",\n      \"tls\": {\n";
            j << "        \"enabled\": true,\n";
            j << "        \"server_name\": \"" << esc(sni.empty() ? server : sni) << "\"";
            if (allow_insecure) {
                j << ",\n        \"insecure\": true";
            }
            j << "\n      }";
        }
        if (network == "ws") {
            j << ",\n      \"transport\": {\n";
            j << "        \"type\": \"ws\",\n";
            j << "        \"path\": \"" << esc(path.empty() ? "/" : path) << "\"";
            if (!host.empty()) {
                j << ",\n        \"headers\": {\"Host\": \"" << esc(host) << "\"}";
            }
            j << "\n      }";
        }
        j << "\n    }\n";

    } else if (protocol == Protocol::SHADOWSOCKS) {
        j << "      \"type\": \"shadowsocks\",\n";
        j << "      \"server\": \"" << esc(server) << "\",\n";
        j << "      \"server_port\": " << port << ",\n";
        j << "      \"method\": \"" << esc(method.empty() ? "aes-128-gcm" : method) << "\",\n";
        j << "      \"password\": \"" << esc(uuid) << "\"\n";
        j << "    }\n";

    } else if (protocol == Protocol::TROJAN) {
        j << "      \"type\": \"trojan\",\n";
        j << "      \"server\": \"" << esc(server) << "\",\n";
        j << "      \"server_port\": " << port << ",\n";
        j << "      \"password\": \"" << esc(uuid) << "\"";

        bool use_tls = (security == "tls" || security.empty());
        if (use_tls) {
            j << ",\n      \"tls\": {\n";
            j << "        \"enabled\": true,\n";
            j << "        \"server_name\": \"" << esc(sni.empty() ? server : sni) << "\"";
            if (allow_insecure) {
                j << ",\n        \"insecure\": true";
            }
            if (!fp.empty()) {
                j << ",\n        \"utls\": {\n";
                j << "          \"enabled\": true,\n";
                j << "          \"fingerprint\": \"" << esc(fp) << "\"\n";
                j << "        }";
            }
            j << "\n      }";
        }
        if (network == "ws") {
            j << ",\n      \"transport\": {\n";
            j << "        \"type\": \"ws\",\n";
            j << "        \"path\": \"" << esc(path.empty() ? "/" : path) << "\"\n";
            j << "      }";
        }
        j << "\n    }\n";
    } else {
        j << "      \"type\": \"direct\"\n    }\n";
    }

    j << "  ]\n";
    j << "}\n";

    return j.str();
}

} // namespace proxy
