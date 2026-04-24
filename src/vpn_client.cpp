#include "vpn_client.hpp"
#include <iostream>
#include <stdexcept>
#include <sys/select.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <chrono>
#include <thread>
#include <optional>

// Parse "10.0.0.2/24" -> ip="10.0.0.2", prefix=24
bool VPNClient::parse_address(const std::string& addr_cidr,
                               std::string& ip, int& prefix)
{
    auto pos = addr_cidr.find('/');
    if (pos == std::string::npos) {
        ip = addr_cidr;
        prefix = 32;
        return true;
    }
    ip = addr_cidr.substr(0, pos);
    try {
        prefix = std::stoi(addr_cidr.substr(pos + 1));
        return true;
    } catch (...) {
        return false;
    }
}

// Convert prefix length to dotted subnet mask
static std::string prefix_to_mask(int prefix) {
    if (prefix <= 0) return "0.0.0.0";
    if (prefix >= 32) return "255.255.255.255";
    uint32_t mask = (~0u) << (32 - prefix);
    struct in_addr a{};
    a.s_addr = htonl(mask);
    return inet_ntoa(a);
}

namespace {

struct EndpointRouteTarget {
    std::string cidr;
    bool ipv6 = false;
};

std::optional<EndpointRouteTarget> resolve_endpoint_route_target(const std::string& endpoint) {
    struct sockaddr_storage addr{};
    socklen_t addr_len = 0;
    if (!wireguard::resolve_endpoint(endpoint, addr, addr_len)) {
        return std::nullopt;
    }

    char host[INET6_ADDRSTRLEN] = {};
    if (addr.ss_family == AF_INET) {
        auto* in = reinterpret_cast<struct sockaddr_in*>(&addr);
        if (!inet_ntop(AF_INET, &in->sin_addr, host, sizeof(host))) {
            return std::nullopt;
        }
        return EndpointRouteTarget{std::string(host) + "/32", false};
    }
    if (addr.ss_family == AF_INET6) {
        auto* in6 = reinterpret_cast<struct sockaddr_in6*>(&addr);
        if (!inet_ntop(AF_INET6, &in6->sin6_addr, host, sizeof(host))) {
            return std::nullopt;
        }
        return EndpointRouteTarget{std::string(host) + "/128", true};
    }
    return std::nullopt;
}

} // namespace

VPNClient::VPNClient() {}

VPNClient::~VPNClient() {
    if (state_.load() != VPNState::Disconnected) {
        should_stop_ = true;
        disconnect();
    }
}

void VPNClient::connect(const config::VPNConfig& cfg) {
    if (state_.load() != VPNState::Disconnected) {
        throw std::runtime_error("Already connected or connecting");
    }

    state_ = VPNState::Connecting;
    should_stop_ = false;
    current_config_ = cfg;
    profile_name_   = cfg.name;

    std::cout << "[VPN] Connecting to profile: " << cfg.name << std::endl;

    try {
        // Check we have at least one peer
        if (cfg.peers.empty()) {
            throw std::runtime_error("No peers configured");
        }
        const auto& peer_cfg = cfg.peers[0];  // Use first peer

        // 1. Create TUN interface
        tun_ = std::make_unique<tun::TunInterface>();
        tun_->open();

        // 2. Configure TUN interface
        setup_tun(cfg.address);

        // 3. Create WireGuard peer
        crypto::Key pub_key = cfg.public_key();
        peer_ = std::make_unique<wireguard::WireGuardPeer>(peer_cfg, cfg.private_key, pub_key);
        peer_->create_socket();

        // 4. Add route to VPN server via existing default gateway (so we don't route the
        //    VPN server traffic through the VPN itself)
        routes_ = std::make_unique<network::RouteManager>();
        routes_->save_default_route();
        auto endpoint_route = resolve_endpoint_route_target(peer_cfg.endpoint);
        if (!endpoint_route) {
            throw std::runtime_error("Could not resolve endpoint for bypass route: " + peer_cfg.endpoint);
        }
        std::string default_gw = endpoint_route->ipv6
            ? routes_->get_default_gateway_ipv6()
            : routes_->get_default_gateway();

        // Route to VPN server via current default gateway (bypass VPN).
        if (default_gw.empty()) {
            throw std::runtime_error("Could not determine default gateway for endpoint: " + peer_cfg.endpoint);
        }
        routes_->add_route(endpoint_route->cidr, "", default_gw);
        peer_gateway_ip_ = default_gw;

        // 5. Perform WireGuard handshake (retry up to 3 times)
        bool connected = false;
        for (int attempt = 1; attempt <= 3 && !should_stop_; attempt++) {
            std::cout << "[VPN] Handshake attempt " << attempt << "/3..." << std::endl;
            try {
                connected = peer_->do_handshake(5000);
                if (connected) break;
            } catch (std::exception& e) {
                std::cerr << "[VPN] Handshake error: " << e.what() << std::endl;
            }
            if (attempt < 3) std::this_thread::sleep_for(std::chrono::seconds(2));
        }

        if (!connected) {
            teardown();
            state_ = VPNState::Disconnected;
            throw std::runtime_error("WireGuard handshake failed after 3 attempts");
        }

        // 6. Set up allowed IP routes through VPN
        setup_routes(peer_cfg);

        // 7. Set up DNS
        if (!cfg.dns.empty()) {
            setup_dns(cfg.dns);
        }

        // 8. Mark as connected and start forwarding threads
        connect_time_ = std::chrono::steady_clock::now();
        last_recv_time_.store(connect_time_.time_since_epoch().count());
        state_ = VPNState::Connected;

        std::cout << "[VPN] Connected! Interface: " << tun_->name() << std::endl;

        tun_to_wg_thread_ = std::thread(&VPNClient::tun_to_wg_loop, this);
        wg_to_tun_thread_ = std::thread(&VPNClient::wg_to_tun_loop, this);
        management_thread_ = std::thread(&VPNClient::management_loop, this);

    } catch (...) {
        teardown();
        state_ = VPNState::Disconnected;
        throw;
    }
}

void VPNClient::setup_tun(const std::string& address) {
    std::string local_ip, peer_ip;
    int prefix;
    if (!parse_address(address, local_ip, prefix)) {
        throw std::runtime_error("Invalid address: " + address);
    }

    // For macOS utun, we configure it as a point-to-point interface
    // The "peer" address is typically the same as local for /32, or gateway for subnet
    // We'll use a derived peer IP (increment last octet)
    struct in_addr ia{};
    if (inet_aton(local_ip.c_str(), &ia) == 0) {
        throw std::runtime_error("Invalid IP address: " + local_ip);
    }

    // Peer IP = local IP with last octet changed (for p2p link)
    uint32_t ip_n = ntohl(ia.s_addr);
    uint32_t peer_n = (ip_n & ~0xFF) | ((ip_n & 0xFF) == 1 ? 2 : 1);
    struct in_addr peer_ia{};
    peer_ia.s_addr = htonl(peer_n);
    peer_ip = inet_ntoa(peer_ia);

    std::string mask = prefix_to_mask(prefix);
    tun_->configure(local_ip, peer_ip, mask, current_config_.mtu);
}

void VPNClient::setup_routes(const config::PeerConfig& peer)
{
    for (const auto& allowed_ip : peer.allowed_ips) {
        routes_->add_route(allowed_ip, tun_->name());
    }
}

void VPNClient::setup_dns(const std::vector<std::string>& dns) {
    try {
        routes_->set_dns(dns);
        std::cout << "[VPN] DNS configured: ";
        for (auto& d : dns) std::cout << d << " ";
        std::cout << std::endl;
    } catch (std::exception& e) {
        std::cerr << "[VPN] Warning: DNS setup failed: " << e.what() << std::endl;
    }
}

void VPNClient::disconnect() {
    auto old_state = state_.exchange(VPNState::Disconnecting);
    if (old_state == VPNState::Disconnected) {
        state_ = VPNState::Disconnected;
        return;
    }

    std::cout << "[VPN] Disconnecting..." << std::endl;
    should_stop_ = true;

    // Close TUN to unblock read threads
    if (tun_) tun_->close();

    // Close UDP socket to unblock recv
    if (peer_) peer_->close_socket();

    // Join threads
    if (tun_to_wg_thread_.joinable())  tun_to_wg_thread_.join();
    if (wg_to_tun_thread_.joinable())  wg_to_tun_thread_.join();
    if (management_thread_.joinable()) management_thread_.join();

    teardown();

    state_ = VPNState::Disconnected;
    std::cout << "[VPN] Disconnected." << std::endl;
}

void VPNClient::teardown() {
    // Restore routes and DNS
    if (routes_) {
        try { routes_->restore_dns(); } catch (...) {}
        try { routes_->remove_all_routes(); } catch (...) {}
        try { routes_->restore_default_route(); } catch (...) {}
        routes_.reset();
    }

    if (peer_) {
        peer_->close_socket();
        peer_.reset();
    }

    if (tun_) {
        tun_->close();
        tun_.reset();
    }
}

void VPNClient::tun_to_wg_loop() {
    std::cout << "[VPN] TUN->WG thread started" << std::endl;

    while (!should_stop_) {
        if (!tun_ || !tun_->is_open()) break;
        if (!peer_) break;

        // Use select with a short timeout so we can check should_stop_
        int tun_fd = tun_->fd();
        fd_set rset;
        FD_ZERO(&rset);
        FD_SET(tun_fd, &rset);
        struct timeval tv{ .tv_sec = 0, .tv_usec = 100000 };  // 100ms

        int ready = select(tun_fd + 1, &rset, nullptr, nullptr, &tv);
        if (ready < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (ready == 0) continue;

        auto pkt = tun_->read_packet();
        if (pkt.empty()) {
            if (should_stop_) break;
            continue;
        }

        if (!peer_->is_connected()) {
            // Drop packet if not connected
            continue;
        }

        if (!peer_->send_packet(pkt.data(), pkt.size())) {
            std::cerr << "[VPN] Failed to send packet (" << pkt.size() << " bytes)" << std::endl;
            // If session died, trigger reconnect
            if (!peer_->is_connected() && auto_reconnect_) {
                state_ = VPNState::Reconnecting;
            }
        }
    }

    std::cout << "[VPN] TUN->WG thread stopped" << std::endl;
}

void VPNClient::wg_to_tun_loop() {
    std::cout << "[VPN] WG->TUN thread started" << std::endl;

    while (!should_stop_) {
        if (!peer_) break;
        if (!tun_ || !tun_->is_open()) break;

        // Use select on UDP socket
        int udp_fd = peer_->socket_fd();
        if (udp_fd < 0) break;

        fd_set rset;
        FD_ZERO(&rset);
        FD_SET(udp_fd, &rset);
        struct timeval tv{ .tv_sec = 0, .tv_usec = 100000 };  // 100ms

        int ready = select(udp_fd + 1, &rset, nullptr, nullptr, &tv);
        if (ready < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (ready == 0) continue;

        auto pkt = peer_->recv_packet();
        if (pkt.empty()) continue;

        // Update last receive time
        last_recv_time_.store(
            std::chrono::steady_clock::now().time_since_epoch().count()
        );

        // Write to TUN
        if (!tun_->write_packet(pkt)) {
            std::cerr << "[VPN] Failed to write packet to TUN" << std::endl;
        }
    }

    std::cout << "[VPN] WG->TUN thread stopped" << std::endl;
}

void VPNClient::management_loop() {
    std::cout << "[VPN] Management thread started" << std::endl;

    while (!should_stop_) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        if (should_stop_) break;

        auto cur_state = state_.load();

        if (cur_state == VPNState::Connected && peer_) {
            // Check keepalive
            if (peer_->keepalive_due()) {
                peer_->send_keepalive();
                peer_->update_keepalive_time();
            }

            // Watchdog: check for session timeout (180 seconds without data)
            if (auto_reconnect_) {
                auto now_rep = std::chrono::steady_clock::now().time_since_epoch().count();
                auto last_rep = last_recv_time_.load();
                using Duration = std::chrono::steady_clock::duration;
                auto elapsed = Duration(now_rep - last_rep);
                auto secs = std::chrono::duration_cast<std::chrono::seconds>(elapsed).count();

                if (secs > 180) {
                    std::cerr << "[VPN] No data received for " << secs
                              << "s, triggering reconnect" << std::endl;
                    state_ = VPNState::Reconnecting;
                }
            }
        }

        if (cur_state == VPNState::Reconnecting) {
            do_reconnect();
        }
    }

    std::cout << "[VPN] Management thread stopped" << std::endl;
}

void VPNClient::do_reconnect() {
    std::cout << "[VPN] Attempting reconnect..." << std::endl;
    state_ = VPNState::Reconnecting;

    // Invalidate old session
    if (peer_) {
        peer_->invalidate_session();
    }

    // Retry handshake up to 5 times
    for (int attempt = 1; attempt <= 5 && !should_stop_; attempt++) {
        std::cout << "[VPN] Reconnect attempt " << attempt << "/5..." << std::endl;

        // Re-create socket if needed
        if (peer_) {
            try {
                peer_->close_socket();
                peer_->create_socket();
                bool ok = peer_->do_handshake(5000);
                if (ok) {
                    state_ = VPNState::Connected;
                    last_recv_time_.store(
                        std::chrono::steady_clock::now().time_since_epoch().count()
                    );
                    std::cout << "[VPN] Reconnected successfully!" << std::endl;
                    return;
                }
            } catch (std::exception& e) {
                std::cerr << "[VPN] Reconnect attempt failed: " << e.what() << std::endl;
            }
        }

        if (attempt < 5) {
            std::this_thread::sleep_for(std::chrono::seconds(5));
        }
    }

    if (!should_stop_) {
        std::cerr << "[VPN] Reconnect failed after 5 attempts. Giving up." << std::endl;
        state_ = VPNState::Disconnected;
        should_stop_ = true;
    }
}

std::string VPNClient::interface_name() const {
    if (tun_) return tun_->name();
    return "";
}

std::string VPNClient::connection_duration() const {
    if (state_.load() != VPNState::Connected) return "N/A";
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
        now - connect_time_
    ).count();
    long h = elapsed / 3600;
    long m = (elapsed % 3600) / 60;
    long s = elapsed % 60;
    char buf[32];
    snprintf(buf, sizeof(buf), "%02ld:%02ld:%02ld", h, m, s);
    return std::string(buf);
}

void VPNClient::wait() {
    if (tun_to_wg_thread_.joinable())  tun_to_wg_thread_.join();
    if (wg_to_tun_thread_.joinable())  wg_to_tun_thread_.join();
    if (management_thread_.joinable()) management_thread_.join();
}
