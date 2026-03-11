#pragma once
#include "../crypto/crypto.hpp"
#include "../crypto/mini_json.hpp"
#include <string>
#include <vector>
#include <optional>

namespace config {

using json = json_ns::value;

// WireGuard traffic obfuscation parameters
struct WgObfsParams {
    int      jc   = 0;   // junk packets count (0 = disabled)
    int      jmin = 40;  // junk packet min size
    int      jmax = 70;  // junk packet max size
    int      s1   = 0;   // extra bytes in initiation
    int      s2   = 0;   // extra bytes in response
    uint32_t h1   = 0;   // magic header type 1
    uint32_t h2   = 0;   // magic header type 2
    uint32_t h3   = 0;   // magic header type 3
    uint32_t h4   = 0;   // magic header type 4

    bool enabled() const { return jc > 0 || h1 != 0 || h2 != 0 || h3 != 0 || h4 != 0; }
};

// Single peer configuration
struct PeerConfig {
    crypto::Key         public_key{};
    std::optional<crypto::Key> preshared_key;
    std::string         endpoint;       // "host:port"
    std::vector<std::string> allowed_ips;
    int                 persistent_keepalive = 0;  // seconds, 0 = disabled
    WgObfsParams       obfs;
};

// Full VPN profile
struct VPNConfig {
    std::string              name;
    crypto::Key              private_key{};
    std::string              address;   // "10.0.0.2/24"
    std::vector<std::string> dns;
    std::vector<PeerConfig>  peers;
    int                      mtu = 1420;

    // Derive our public key
    crypto::Key public_key() const {
        return crypto::public_from_private(private_key);
    }
};

// JSON serialization helpers

inline WgObfsParams wg_obfs_from_json(const json& j) {
    WgObfsParams p;
    if (j.contains("jc"))   p.jc   = j.at("jc").get<int>();
    if (j.contains("jmin")) p.jmin = j.at("jmin").get<int>();
    if (j.contains("jmax")) p.jmax = j.at("jmax").get<int>();
    if (j.contains("s1"))   p.s1   = j.at("s1").get<int>();
    if (j.contains("s2"))   p.s2   = j.at("s2").get<int>();
    if (j.contains("h1"))   p.h1   = j.at("h1").get<uint32_t>();
    if (j.contains("h2"))   p.h2   = j.at("h2").get<uint32_t>();
    if (j.contains("h3"))   p.h3   = j.at("h3").get<uint32_t>();
    if (j.contains("h4"))   p.h4   = j.at("h4").get<uint32_t>();
    return p;
}

inline json wg_obfs_to_json(const WgObfsParams& p) {
    json j;
    j["jc"]   = p.jc;
    j["jmin"] = p.jmin;
    j["jmax"] = p.jmax;
    j["s1"]   = p.s1;
    j["s2"]   = p.s2;
    j["h1"]   = p.h1;
    j["h2"]   = p.h2;
    j["h3"]   = p.h3;
    j["h4"]   = p.h4;
    return j;
}

inline PeerConfig peer_from_json(const json& j) {
    PeerConfig p;
    p.public_key = crypto::key_from_base64(j.at("public_key").get<std::string>());
    if (j.contains("preshared_key") && !j.at("preshared_key").get<std::string>().empty()) {
        p.preshared_key = crypto::key_from_base64(j.at("preshared_key").get<std::string>());
    }
    p.endpoint = j.at("endpoint").get<std::string>();
    if (j.contains("allowed_ips")) {
        for (auto& ip : j.at("allowed_ips")) {
            p.allowed_ips.push_back(ip.get<std::string>());
        }
    }
    if (j.contains("persistent_keepalive"))
        p.persistent_keepalive = j.at("persistent_keepalive").get<int>();
    p.obfs = wg_obfs_from_json(j);
    return p;
}

inline json peer_to_json(const PeerConfig& p) {
    json j;
    j["public_key"] = crypto::base64_encode(p.public_key);
    if (p.preshared_key) {
        j["preshared_key"] = crypto::base64_encode(*p.preshared_key);
    }
    j["endpoint"]   = p.endpoint;
    // Build allowed_ips array
    json ips = json::array();
    for (auto& ip : p.allowed_ips) ips.push_back(ip);
    j["allowed_ips"] = ips;
    j["persistent_keepalive"] = p.persistent_keepalive;
    // merge obfuscation params
    auto ap = wg_obfs_to_json(p.obfs);
    j.merge_patch(ap);
    return j;
}

inline VPNConfig config_from_json(const json& j) {
    VPNConfig c;
    c.name        = j.at("name").get<std::string>();
    c.private_key = crypto::key_from_base64(j.at("private_key").get<std::string>());
    c.address     = j.at("address").get<std::string>();
    if (j.contains("dns")) {
        for (auto& d : j.at("dns")) c.dns.push_back(d.get<std::string>());
    }
    if (j.contains("mtu")) c.mtu = j.at("mtu").get<int>();
    if (j.contains("peers")) {
        for (auto& p : j.at("peers")) c.peers.push_back(peer_from_json(p));
    }
    return c;
}

inline json config_to_json(const VPNConfig& c) {
    json j;
    j["name"]        = c.name;
    j["private_key"] = crypto::base64_encode(c.private_key);
    j["address"]     = c.address;
    // dns array
    json dns_arr = json::array();
    for (auto& d : c.dns) dns_arr.push_back(d);
    j["dns"]  = dns_arr;
    j["mtu"]  = c.mtu;
    json peers = json::array();
    for (auto& p : c.peers) peers.push_back(peer_to_json(p));
    j["peers"] = peers;
    return j;
}

// ---- Persistence functions (implemented in config.cpp) ----

std::string get_config_dir();
void        ensure_config_dir();
std::string config_path(const std::string& name);

void        save_config(const VPNConfig& cfg);
VPNConfig   load_config(const std::string& name);
VPNConfig   load_config_from_file(const std::string& filepath);
std::vector<std::string> list_configs();
void        remove_config(const std::string& name);
bool        config_exists(const std::string& name);

} // namespace config
