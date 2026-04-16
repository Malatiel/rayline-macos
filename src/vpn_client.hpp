#pragma once
#include "config/config.hpp"
#include "tun/tun_interface.hpp"
#include "wireguard/wireguard.hpp"
#include "network/route_manager.hpp"

#include <atomic>
#include <thread>
#include <memory>
#include <string>
#include <chrono>

// VPN client states
enum class VPNState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Disconnecting
};

inline std::string vpn_state_str(VPNState s) {
    switch (s) {
        case VPNState::Disconnected:  return "Disconnected";
        case VPNState::Connecting:    return "Connecting";
        case VPNState::Connected:     return "Connected";
        case VPNState::Reconnecting:  return "Reconnecting";
        case VPNState::Disconnecting: return "Disconnecting";
        default:                       return "Unknown";
    }
}

class VPNClient {
public:
    VPNClient();
    ~VPNClient();

    // Connect using a loaded config profile
    // Blocks until connected or throws on failure
    void connect(const config::VPNConfig& cfg);

    // Disconnect the VPN
    void disconnect();

    // Get current state
    VPNState state() const { return state_.load(); }
    std::string state_str() const { return vpn_state_str(state()); }

    // Get current interface name
    std::string interface_name() const;

    // Get connected profile name
    std::string profile_name() const { return profile_name_; }

    // Duration of current connection
    std::string connection_duration() const;

    // Set auto-reconnect (default: true)
    void set_auto_reconnect(bool v) { auto_reconnect_ = v; }

    bool is_connected() const {
        return state_.load() == VPNState::Connected;
    }

    // Wait for disconnect (blocks)
    void wait();

private:
    // Parse address like "10.0.0.2/24" into IP and mask
    static bool parse_address(const std::string& addr_cidr,
                               std::string& ip, int& prefix);

    // Configure the TUN interface after opening
    void setup_tun(const std::string& address);

    // Set up routes for allowed IPs
    void setup_routes(const config::PeerConfig& peer,
                      const std::string& peer_gateway_ip);

    // Set up DNS
    void setup_dns(const std::vector<std::string>& dns);

    // Tear down everything
    void teardown();

    // Main packet forwarding loop: TUN -> WireGuard
    void tun_to_wg_loop();

    // Main packet forwarding loop: WireGuard -> TUN
    void wg_to_tun_loop();

    // Management loop: keepalive, reconnect watchdog
    void management_loop();

    // Perform reconnect
    void do_reconnect();

    std::atomic<VPNState>  state_{VPNState::Disconnected};
    std::atomic<bool>      should_stop_{false};
    bool                   auto_reconnect_ = true;

    config::VPNConfig      current_config_;
    std::string            profile_name_;

    std::unique_ptr<tun::TunInterface>         tun_;
    std::unique_ptr<wireguard::WireGuardPeer>  peer_;
    std::unique_ptr<network::RouteManager>     routes_;

    std::thread            tun_to_wg_thread_;
    std::thread            wg_to_tun_thread_;
    std::thread            management_thread_;

    std::chrono::steady_clock::time_point connect_time_;

    // Last successful data receive time (for reconnect detection)
    std::atomic<std::chrono::steady_clock::time_point::rep> last_recv_time_{
        std::chrono::steady_clock::now().time_since_epoch().count()
    };

    // Peer gateway (for route setup)
    std::string peer_gateway_ip_;
};
