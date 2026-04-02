#include "route_manager.hpp"

#include <sys/socket.h>
#include <net/route.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <sstream>
#include <iostream>
#include <fstream>
#include <stdexcept>
#include <array>
#include <memory>

namespace network {

// Returns true if s looks like a valid IPv4/IPv6 address (only safe chars).
// Accepts digits, dots, colons, and hex letters — nothing that would allow
// shell injection.
static bool is_valid_ip(const std::string& s) {
    if (s.empty() || s.size() > 45) return false;
    for (unsigned char c : s) {
        if (!isdigit(c) && c != '.' && c != ':' &&
            !(c >= 'a' && c <= 'f') && !(c >= 'A' && c <= 'F'))
            return false;
    }
    return true;
}

// Returns true if the string is safe to embed inside a double-quoted shell
// argument (no double-quote, backtick, dollar sign, backslash or control chars).
static bool is_safe_shell_string(const std::string& s) {
    if (s.empty()) return false;
    for (unsigned char c : s) {
        if (c == '"' || c == '\'' || c == '`' || c == '$' ||
            c == '\\' || c < 0x20)
            return false;
    }
    return true;
}

// Execute a shell command and capture stdout
static std::string exec_cmd(const std::string& cmd) {
    std::array<char, 256> buf;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd.c_str(), "r"), pclose);
    if (!pipe) return "";
    while (fgets(buf.data(), buf.size(), pipe.get()) != nullptr) {
        result += buf.data();
    }
    // Trim trailing newline
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r'))
        result.pop_back();
    return result;
}

// Run a system command silently
static int run_cmd(const std::string& cmd) {
    std::cout << "[ROUTE] " << cmd << std::endl;
    return system(cmd.c_str());
}

// Parse CIDR into address and prefix length
static bool parse_cidr(const std::string& cidr, std::string& addr, int& prefix) {
    auto pos = cidr.find('/');
    if (pos == std::string::npos) {
        addr = cidr;
        prefix = 32;
        return true;
    }
    addr = cidr.substr(0, pos);
    try {
        prefix = std::stoi(cidr.substr(pos + 1));
    } catch (...) {
        return false;
    }
    return true;
}

// Convert prefix length to dotted netmask string
static std::string prefix_to_mask(int prefix) {
    if (prefix < 0 || prefix > 32) return "255.255.255.255";
    uint32_t mask = prefix == 0 ? 0 : (~0u << (32 - prefix));
    struct in_addr a{};
    a.s_addr = htonl(mask);
    return inet_ntoa(a);
}

RouteManager::RouteManager() {}

RouteManager::~RouteManager() {
    // Don't auto-remove; caller is responsible
}

void RouteManager::add_route(const std::string& cidr, const std::string& iface,
                              const std::string& gateway)
{
    std::string addr;
    int prefix;
    if (!parse_cidr(cidr, addr, prefix)) {
        throw std::runtime_error("Invalid CIDR: " + cidr);
    }

    std::string mask = prefix_to_mask(prefix);
    std::string cmd;

    if (!gateway.empty() && !is_valid_ip(gateway)) {
        throw std::runtime_error("Invalid gateway IP: " + gateway);
    }
    if (!iface.empty() && !is_safe_shell_string(iface)) {
        throw std::runtime_error("Invalid interface name: " + iface);
    }

    if (addr == "0.0.0.0" && prefix == 0) {
        // Default route: use -net 0.0.0.0/1 and 128.0.0.0/1 trick to
        // avoid overriding the system default route entry (which we need
        // to reach the VPN server). This is the standard WireGuard approach.
        if (!gateway.empty()) {
            cmd = "route add -net 0.0.0.0/1 " + gateway;
            run_cmd(cmd);
            added_routes_.push_back({"0.0.0.0/1", iface, gateway});
            cmd = "route add -net 128.0.0.0/1 " + gateway;
            run_cmd(cmd);
            added_routes_.push_back({"128.0.0.0/1", iface, gateway});
        } else {
            cmd = "route add -net 0.0.0.0/1 -interface " + iface;
            run_cmd(cmd);
            added_routes_.push_back({"0.0.0.0/1", iface, ""});
            cmd = "route add -net 128.0.0.0/1 -interface " + iface;
            run_cmd(cmd);
            added_routes_.push_back({"128.0.0.0/1", iface, ""});
        }
        return;
    }

    if (!gateway.empty()) {
        cmd = "route add -net " + addr + " -netmask " + mask + " " + gateway;
    } else {
        cmd = "route add -net " + addr + " -netmask " + mask + " -interface " + iface;
    }

    int rc = run_cmd(cmd);
    if (rc != 0) {
        std::cerr << "[ROUTE] Warning: route add returned " << rc << std::endl;
    }
    added_routes_.push_back({cidr, iface, gateway});
}

void RouteManager::delete_route(const std::string& cidr, const std::string& iface,
                                 const std::string& gateway)
{
    std::string addr;
    int prefix;
    if (!parse_cidr(cidr, addr, prefix)) {
        std::cerr << "[ROUTE] Invalid CIDR: " << cidr << std::endl;
        return;
    }

    std::string mask = prefix_to_mask(prefix);
    std::string cmd;

    if (addr == "0.0.0.0" && prefix == 0) {
        // Remove the split routes
        run_cmd("route delete -net 0.0.0.0/1");
        run_cmd("route delete -net 128.0.0.0/1");
        return;
    }

    if (!gateway.empty()) {
        cmd = "route delete -net " + addr + " -netmask " + mask + " " + gateway;
    } else {
        cmd = "route delete -net " + addr + " -netmask " + mask + " -interface " + iface;
    }
    run_cmd(cmd);
}

void RouteManager::remove_all_routes() {
    // Remove in reverse order
    for (int i = (int)added_routes_.size() - 1; i >= 0; i--) {
        auto& r = added_routes_[i];
        delete_route(r.cidr, r.iface, r.gateway);
    }
    added_routes_.clear();
}

std::string RouteManager::get_default_gateway() {
    // Parse netstat -nr output for default route
    std::string out = exec_cmd("netstat -nr -f inet 2>/dev/null | grep '^default'");
    if (out.empty()) return "";
    // Format: "default  192.168.1.1  UGScg  en0"
    std::istringstream iss(out);
    std::string dest, gw;
    iss >> dest >> gw;
    return gw;
}

std::string RouteManager::get_primary_service() {
    // Determine the active network service by finding the interface used for
    // the default route, then mapping it back to a networksetup service name.
    std::string iface = exec_cmd("route -n get default 2>/dev/null | awk '/interface:/{print $2}'");
    if (!iface.empty() && is_safe_shell_string(iface)) {
        // Map interface (e.g. "en0") to service name (e.g. "Wi-Fi")
        std::string order = exec_cmd("networksetup -listallhardwareports 2>/dev/null");
        std::istringstream iss(order);
        std::string line, current_service;
        while (std::getline(iss, line)) {
            // Lines look like:
            //   Hardware Port: Wi-Fi
            //   Device: en0
            if (line.find("Hardware Port: ") == 0) {
                current_service = line.substr(15);
            } else if (line.find("Device: ") == 0) {
                std::string dev = line.substr(8);
                // Trim whitespace
                while (!dev.empty() && (dev.back() == ' ' || dev.back() == '\r'))
                    dev.pop_back();
                if (dev == iface && !current_service.empty()) {
                    return current_service;
                }
            }
        }
    }
    // Fallback: first non-asterisk service
    std::string fallback = exec_cmd("networksetup -listallnetworkservices 2>/dev/null | grep -v '^An asterisk' | head -2 | tail -1");
    return fallback;
}

void RouteManager::save_default_route() {
    if (default_route_saved_) return;
    saved_default_gw_ = get_default_gateway();
    default_route_saved_ = true;
    std::cout << "[ROUTE] Saved default gateway: " << saved_default_gw_ << std::endl;
}

void RouteManager::restore_default_route() {
    if (!default_route_saved_ || saved_default_gw_.empty()) return;
    std::string cmd = "route add default " + saved_default_gw_;
    run_cmd(cmd);
    default_route_saved_ = false;
}

bool RouteManager::set_dns(const std::vector<std::string>& servers) {
    if (servers.empty()) return true;

    // Save original DNS first
    saved_dns_service_ = get_primary_service();
    if (!saved_dns_service_.empty() && is_safe_shell_string(saved_dns_service_)) {
        std::string out = exec_cmd("networksetup -getdnsservers \"" + saved_dns_service_ + "\" 2>/dev/null");
        if (!out.empty() && out != "There aren't any DNS Servers set on " + saved_dns_service_ + ".") {
            std::istringstream iss(out);
            std::string srv;
            while (std::getline(iss, srv)) {
                if (!srv.empty()) saved_dns_servers_.push_back(srv);
            }
        }
    }

    // Save original /etc/resolv.conf contents before overwriting
    {
        std::ifstream ifs("/etc/resolv.conf");
        if (ifs.is_open()) {
            std::ostringstream ss;
            ss << ifs.rdbuf();
            saved_resolv_conf_ = ss.str();
        }
    }

    // Write /etc/resolv.conf as well (for applications that use it directly)
    FILE* f = fopen("/etc/resolv.conf", "w");
    if (f) {
        for (auto& s : servers) {
            fprintf(f, "nameserver %s\n", s.c_str());
        }
        fclose(f);
    }

    // Use networksetup to set DNS
    if (!saved_dns_service_.empty() && is_safe_shell_string(saved_dns_service_)) {
        std::string cmd = "networksetup -setdnsservers \"" + saved_dns_service_ + "\"";
        for (auto& s : servers) {
            if (is_valid_ip(s)) {
                cmd += " " + s;
            } else {
                std::cerr << "[ROUTE] Skipping invalid DNS server: " << s << std::endl;
            }
        }
        run_cmd(cmd);
    }

    dns_modified_ = true;
    return true;
}

void RouteManager::restore_dns() {
    if (!dns_modified_) return;

    // Restore networksetup DNS
    if (!saved_dns_service_.empty() && is_safe_shell_string(saved_dns_service_)) {
        std::string cmd = "networksetup -setdnsservers \"" + saved_dns_service_ + "\"";
        if (saved_dns_servers_.empty()) {
            cmd += " Empty";
        } else {
            for (auto& s : saved_dns_servers_) {
                if (is_valid_ip(s)) cmd += " " + s;
            }
        }
        run_cmd(cmd);
    }

    // Restore /etc/resolv.conf to its original contents
    if (!saved_resolv_conf_.empty()) {
        FILE* f = fopen("/etc/resolv.conf", "w");
        if (f) {
            fwrite(saved_resolv_conf_.data(), 1, saved_resolv_conf_.size(), f);
            fclose(f);
            std::cout << "[ROUTE] Restored /etc/resolv.conf" << std::endl;
        }
        saved_resolv_conf_.clear();
    }

    dns_modified_ = false;
}

} // namespace network
