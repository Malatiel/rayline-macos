#include "route_manager.hpp"

#include <sys/wait.h>
#include <arpa/inet.h>

#include <cstring>
#include <sstream>
#include <iostream>
#include <stdexcept>
#include <unistd.h>
#include <fcntl.h>

namespace network {

// Returns true if s looks like a valid IPv4/IPv6 address (only safe chars).
static bool is_valid_ip(const std::string& s) {
    if (s.empty() || s.size() > 45) return false;
    auto percent = s.find('%');
    std::string ip_part = percent == std::string::npos ? s : s.substr(0, percent);
    std::string zone = percent == std::string::npos ? "" : s.substr(percent + 1);
    if (ip_part.empty() || (!zone.empty() && ip_part.find(':') == std::string::npos)) {
        return false;
    }
    for (unsigned char c : ip_part) {
        if (!isdigit(c) && c != '.' && c != ':' &&
            !(c >= 'a' && c <= 'f') && !(c >= 'A' && c <= 'F'))
            return false;
    }
    for (unsigned char c : zone) {
        if (!std::isalnum(c) && c != '_' && c != '.' && c != '-') {
            return false;
        }
    }
    return true;
}

static bool is_ipv6_addr(const std::string& s) {
    return s.find(':') != std::string::npos;
}

// Returns true if the string is safe for use as an interface/service name
// (no shell-special chars or control chars).
static bool is_safe_shell_string(const std::string& s) {
    if (s.empty()) return false;
    for (unsigned char c : s) {
        if (c == '"' || c == '\'' || c == '`' || c == '$' ||
            c == '\\' || c < 0x20)
            return false;
    }
    return true;
}

// Execute a command with arguments directly (no shell), capture stdout
static std::string exec_argv(const std::vector<std::string>& args) {
    if (args.empty()) return "";

    int pipefd[2];
    if (pipe(pipefd) < 0) return "";

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return "";
    }

    if (pid == 0) {
        // Child
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);
        // Redirect stderr to /dev/null
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) { dup2(devnull, STDERR_FILENO); close(devnull); }

        std::vector<const char*> argv;
        for (auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execvp(argv[0], const_cast<char* const*>(argv.data()));
        _exit(127);
    }

    // Parent
    close(pipefd[1]);
    std::string result;
    char buf[256];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) {
        result.append(buf, (size_t)n);
    }
    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    // Trim trailing newlines
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r'))
        result.pop_back();
    return result;
}

// Run a command with arguments directly (no shell), return exit code
static int run_argv(const std::vector<std::string>& args) {
    // Log the command
    std::cout << "[ROUTE]";
    for (auto& a : args) std::cout << " " << a;
    std::cout << std::endl;

    pid_t pid = fork();
    if (pid < 0) return -1;

    if (pid == 0) {
        std::vector<const char*> argv;
        for (auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execvp(argv[0], const_cast<char* const*>(argv.data()));
        _exit(127);
    }

    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

// Parse CIDR into address and prefix length
static bool parse_cidr(const std::string& cidr, std::string& addr, int& prefix) {
    auto pos = cidr.find('/');
    if (pos == std::string::npos) {
        addr = cidr;
        prefix = is_ipv6_addr(addr) ? 128 : 32;
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

static void run_add_or_change(const std::vector<std::string>& add_cmd,
                              const std::vector<std::string>& change_cmd,
                              const std::string& context)
{
    int rc = run_argv(add_cmd);
    if (rc == 0) return;

    std::cerr << "[ROUTE] route add returned " << rc
              << ", trying route change" << std::endl;
    int change_rc = run_argv(change_cmd);
    if (change_rc != 0) {
        throw std::runtime_error(context + " failed (add rc=" +
                                 std::to_string(rc) + ", change rc=" +
                                 std::to_string(change_rc) + ")");
    }
}

static std::vector<std::string> ipv6_route_cmd(const std::string& action,
                                                const std::string& addr,
                                                int prefix,
                                                const std::string& iface,
                                                const std::string& gateway)
{
    std::vector<std::string> cmd = {
        "route", action, "-inet6", "-net", addr, "-prefixlen", std::to_string(prefix)
    };
    if (!gateway.empty()) {
        cmd.push_back(gateway);
    } else {
        cmd.push_back("-interface");
        cmd.push_back(iface);
    }
    return cmd;
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

    bool is_v6 = is_ipv6_addr(addr);
    if (is_v6) {
        if (prefix < 0 || prefix > 128) {
            throw std::runtime_error("Invalid IPv6 prefix: " + cidr);
        }
    } else if (prefix < 0 || prefix > 32) {
        throw std::runtime_error("Invalid IPv4 prefix: " + cidr);
    }
    if (!is_valid_ip(addr)) {
        throw std::runtime_error("Invalid route address: " + addr);
    }
    if (!gateway.empty() && !is_valid_ip(gateway)) {
        throw std::runtime_error("Invalid gateway IP: " + gateway);
    }
    if (!gateway.empty() && is_ipv6_addr(gateway) != is_v6) {
        throw std::runtime_error("Gateway family does not match route: " + cidr);
    }
    if (!iface.empty() && !is_safe_shell_string(iface)) {
        throw std::runtime_error("Invalid interface name: " + iface);
    }
    if (gateway.empty() && iface.empty()) {
        throw std::runtime_error("Route requires gateway or interface: " + cidr);
    }

    if (is_v6) {
        if (prefix == 0 && addr == "::") {
            std::vector<Route> staged;
            try {
                run_add_or_change(
                    ipv6_route_cmd("add", "::", 1, iface, gateway),
                    ipv6_route_cmd("change", "::", 1, iface, gateway),
                    "route add"
                );
                staged.push_back({"::/1", iface, gateway});
                run_add_or_change(
                    ipv6_route_cmd("add", "8000::", 1, iface, gateway),
                    ipv6_route_cmd("change", "8000::", 1, iface, gateway),
                    "route add"
                );
                staged.push_back({"8000::/1", iface, gateway});
            } catch (...) {
                for (const auto& r : staged) delete_route(r.cidr, r.iface, r.gateway);
                throw;
            }
            added_routes_.insert(added_routes_.end(), staged.begin(), staged.end());
            return;
        }

        run_add_or_change(
            ipv6_route_cmd("add", addr, prefix, iface, gateway),
            ipv6_route_cmd("change", addr, prefix, iface, gateway),
            "route add"
        );
        added_routes_.push_back({cidr, iface, gateway});
        return;
    }

    std::string mask = prefix_to_mask(prefix);

    if (addr == "0.0.0.0" && prefix == 0) {
        // Default route: use -net 0.0.0.0/1 and 128.0.0.0/1 trick
        std::vector<Route> staged;
        auto add_v4 = [&](const std::string& net) {
            if (!gateway.empty()) {
                run_add_or_change(
                    {"route", "add", "-net", net, gateway},
                    {"route", "change", "-net", net, gateway},
                    "route add"
                );
                staged.push_back({net, iface, gateway});
            } else {
                run_add_or_change(
                    {"route", "add", "-net", net, "-interface", iface},
                    {"route", "change", "-net", net, "-interface", iface},
                    "route add"
                );
                staged.push_back({net, iface, ""});
            }
        };
        try {
            add_v4("0.0.0.0/1");
            add_v4("128.0.0.0/1");
        } catch (...) {
            for (const auto& r : staged) delete_route(r.cidr, r.iface, r.gateway);
            throw;
        }
        added_routes_.insert(added_routes_.end(), staged.begin(), staged.end());
        return;
    }

    std::vector<std::string> cmd;
    if (!gateway.empty()) {
        cmd = {"route", "add", "-net", addr, "-netmask", mask, gateway};
    } else {
        cmd = {"route", "add", "-net", addr, "-netmask", mask, "-interface", iface};
    }

    std::vector<std::string> change_cmd = cmd;
    change_cmd[1] = "change";
    run_add_or_change(cmd, change_cmd, "route add");
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

    bool is_v6 = is_ipv6_addr(addr);

    if (is_v6) {
        if (addr == "::" && prefix == 0) {
            run_argv({"route", "delete", "-inet6", "-net", "::", "-prefixlen", "1"});
            run_argv({"route", "delete", "-inet6", "-net", "8000::", "-prefixlen", "1"});
            return;
        }
        run_argv(ipv6_route_cmd("delete", addr, prefix, iface, gateway));
        return;
    }

    std::string mask = prefix_to_mask(prefix);

    if (addr == "0.0.0.0" && prefix == 0) {
        run_argv({"route", "delete", "-net", "0.0.0.0/1"});
        run_argv({"route", "delete", "-net", "128.0.0.0/1"});
        return;
    }

    std::vector<std::string> cmd;
    if (!gateway.empty()) {
        cmd = {"route", "delete", "-net", addr, "-netmask", mask, gateway};
    } else {
        cmd = {"route", "delete", "-net", addr, "-netmask", mask, "-interface", iface};
    }
    run_argv(cmd);
}

void RouteManager::remove_all_routes() {
    for (int i = (int)added_routes_.size() - 1; i >= 0; i--) {
        auto& r = added_routes_[i];
        delete_route(r.cidr, r.iface, r.gateway);
    }
    added_routes_.clear();
}

static std::string parse_gateway_from_route_output(const std::string& out) {
    if (out.empty()) return "";
    std::istringstream iss(out);
    std::string line;
    while (std::getline(iss, line)) {
        auto pos = line.find("gateway:");
        if (pos != std::string::npos) {
            std::string gw = line.substr(pos + 8);
            // Trim whitespace
            while (!gw.empty() && gw.front() == ' ') gw.erase(gw.begin());
            while (!gw.empty() && (gw.back() == ' ' || gw.back() == '\r')) gw.pop_back();
            return gw;
        }
    }
    return "";
}

std::string RouteManager::get_default_gateway() {
    // Use route to get the IPv4 default gateway directly.
    return parse_gateway_from_route_output(exec_argv({"route", "-n", "get", "default"}));
}

std::string RouteManager::get_default_gateway_ipv6() {
    return parse_gateway_from_route_output(exec_argv({"route", "-n", "get", "-inet6", "default"}));
}

std::string RouteManager::get_primary_service() {
    // Determine the active network service by finding the interface used for
    // the default route, then mapping it back to a networksetup service name.
    std::string route_out = exec_argv({"route", "-n", "get", "default"});
    std::string iface;
    {
        std::istringstream iss(route_out);
        std::string line;
        while (std::getline(iss, line)) {
            auto pos = line.find("interface:");
            if (pos != std::string::npos) {
                iface = line.substr(pos + 10);
                while (!iface.empty() && iface.front() == ' ') iface.erase(iface.begin());
                while (!iface.empty() && (iface.back() == ' ' || iface.back() == '\r')) iface.pop_back();
                break;
            }
        }
    }

    if (!iface.empty() && is_safe_shell_string(iface)) {
        std::string order = exec_argv({"networksetup", "-listallhardwareports"});
        std::istringstream iss(order);
        std::string line, current_service;
        while (std::getline(iss, line)) {
            if (line.find("Hardware Port: ") == 0) {
                current_service = line.substr(15);
            } else if (line.find("Device: ") == 0) {
                std::string dev = line.substr(8);
                while (!dev.empty() && (dev.back() == ' ' || dev.back() == '\r'))
                    dev.pop_back();
                if (dev == iface && !current_service.empty()) {
                    return current_service;
                }
            }
        }
    }
    // Fallback: first non-asterisk service
    std::string list = exec_argv({"networksetup", "-listallnetworkservices"});
    std::istringstream iss(list);
    std::string line;
    while (std::getline(iss, line)) {
        if (line.find("An asterisk") != std::string::npos) continue;
        if (!line.empty()) return line;
    }
    return "";
}

void RouteManager::save_default_route() {
    if (default_route_saved_) return;
    saved_default_gw_ = get_default_gateway();
    default_route_saved_ = true;
    std::cout << "[ROUTE] Saved default gateway: " << saved_default_gw_ << std::endl;
}

void RouteManager::restore_default_route() {
    if (!default_route_saved_ || saved_default_gw_.empty()) return;
    run_argv({"route", "add", "default", saved_default_gw_});
    default_route_saved_ = false;
}

bool RouteManager::set_dns(const std::vector<std::string>& servers) {
    if (servers.empty()) return true;

    // Save original DNS first
    saved_dns_service_ = get_primary_service();
    if (!saved_dns_service_.empty() && is_safe_shell_string(saved_dns_service_)) {
        std::string out = exec_argv({"networksetup", "-getdnsservers", saved_dns_service_});
        if (!out.empty() && out.find("There aren't any DNS Servers") == std::string::npos) {
            std::istringstream iss(out);
            std::string srv;
            while (std::getline(iss, srv)) {
                if (!srv.empty()) saved_dns_servers_.push_back(srv);
            }
        }
    }

    // Use networksetup to set DNS
    if (!saved_dns_service_.empty() && is_safe_shell_string(saved_dns_service_)) {
        std::vector<std::string> cmd = {"networksetup", "-setdnsservers", saved_dns_service_};
        for (auto& s : servers) {
            if (is_valid_ip(s)) {
                cmd.push_back(s);
            } else {
                std::cerr << "[ROUTE] Skipping invalid DNS server: " << s << std::endl;
            }
        }
        run_argv(cmd);
    }

    dns_modified_ = true;
    return true;
}

void RouteManager::restore_dns() {
    if (!dns_modified_) return;

    if (!saved_dns_service_.empty() && is_safe_shell_string(saved_dns_service_)) {
        std::vector<std::string> cmd = {"networksetup", "-setdnsservers", saved_dns_service_};
        if (saved_dns_servers_.empty()) {
            cmd.push_back("Empty");
        } else {
            for (auto& s : saved_dns_servers_) {
                if (is_valid_ip(s)) cmd.push_back(s);
            }
        }
        run_argv(cmd);
    }

    dns_modified_ = false;
}

} // namespace network
