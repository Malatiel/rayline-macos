#pragma once
#include <string>
#include <vector>

namespace network {

// Manages macOS routes and DNS settings for the VPN

class RouteManager {
public:
    RouteManager();
    ~RouteManager();

    // Add a route for a CIDR prefix via the given interface (or gateway)
    // cidr: e.g. "0.0.0.0/0", "10.0.0.0/8"
    // iface: e.g. "utun3"
    // gateway: optional gateway IP (if empty, uses interface)
    void add_route(const std::string& cidr, const std::string& iface,
                   const std::string& gateway = "");

    // Delete a route
    void delete_route(const std::string& cidr, const std::string& iface,
                      const std::string& gateway = "");

    // Delete all routes that were added by this manager
    void remove_all_routes();

    // Set DNS servers (writes to /etc/resolv.conf backup and uses networksetup)
    // Returns true on success
    bool set_dns(const std::vector<std::string>& servers);

    // Restore original DNS settings
    void restore_dns();

    // Get the default gateway (for saving before we override)
    std::string get_default_gateway();

    // Get the primary network service name (for networksetup)
    std::string get_primary_service();

    // Save the original default route so we can restore it
    void save_default_route();

    // Restore saved default route
    void restore_default_route();

private:
    struct Route {
        std::string cidr;
        std::string iface;
        std::string gateway;
    };

    std::vector<Route>   added_routes_;
    std::string          saved_default_gw_;
    std::string          saved_dns_service_;
    std::vector<std::string> saved_dns_servers_;
    std::string          saved_resolv_conf_;
    bool                 dns_modified_ = false;
    bool                 default_route_saved_ = false;
};

} // namespace network
