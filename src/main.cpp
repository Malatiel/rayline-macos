#include "vpn_client.hpp"
#include "config/config.hpp"
#include "crypto/crypto.hpp"

#include <iostream>
#include <string>
#include <vector>
#include <csignal>
#include <atomic>
#include <thread>
#include <unistd.h>
#include <mach-o/dyld.h>

// Global VPN client instance for signal handler
static VPNClient* g_vpn_client = nullptr;
static std::atomic<bool> g_interrupted{false};

void signal_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) {
        std::cout << "\n[MAIN] Signal " << sig << " received. Disconnecting..." << std::endl;
        g_interrupted = true;
        if (g_vpn_client) {
            g_vpn_client->disconnect();
        }
    }
}

void print_usage(const std::string& prog) {
    std::cout << "Usage:\n"
              << "  " << prog << " add <config.json>         Import a VPN config\n"
              << "  " << prog << " list                       List saved configs\n"
              << "  " << prog << " connect <name>             Connect to VPN\n"
              << "  " << prog << " disconnect                 Disconnect from VPN\n"
              << "  " << prog << " status                     Show connection status\n"
              << "  " << prog << " remove <name>              Remove a saved config\n"
              << "  " << prog << " keygen                     Generate a WireGuard key pair\n"
              << "\n"
              << "Config file format (JSON):\n"
              << "  {\n"
              << "    \"name\": \"my-server\",\n"
              << "    \"private_key\": \"<base64>\",\n"
              << "    \"address\": \"10.0.0.2/24\",\n"
              << "    \"dns\": [\"1.1.1.1\"],\n"
              << "    \"peers\": [{\n"
              << "      \"public_key\": \"<base64>\",\n"
              << "      \"endpoint\": \"1.2.3.4:51820\",\n"
              << "      \"allowed_ips\": [\"0.0.0.0/0\"],\n"
              << "      \"persistent_keepalive\": 25,\n"
              << "      \"jc\": 4, \"jmin\": 40, \"jmax\": 70,\n"
              << "      \"h1\": 1, \"h2\": 2, \"h3\": 3, \"h4\": 4\n"
              << "    }]\n"
              << "  }\n";
}

int cmd_add(const std::string& filepath) {
    try {
        auto cfg = config::load_config_from_file(filepath);
        config::save_config(cfg);
        std::cout << "Config '" << cfg.name << "' imported successfully." << std::endl;
        return 0;
    } catch (std::exception& e) {
        std::cerr << "Error importing config: " << e.what() << std::endl;
        return 1;
    }
}

int cmd_list() {
    try {
        auto names = config::list_configs();
        if (names.empty()) {
            std::cout << "No configs found. Use 'add <config.json>' to import one." << std::endl;
        } else {
            std::cout << "Saved configs:" << std::endl;
            for (auto& n : names) {
                std::cout << "  - " << n << std::endl;
            }
        }
        return 0;
    } catch (std::exception& e) {
        std::cerr << "Error listing configs: " << e.what() << std::endl;
        return 1;
    }
}

int cmd_remove(const std::string& name) {
    try {
        config::remove_config(name);
        return 0;
    } catch (std::exception& e) {
        std::cerr << "Error removing config: " << e.what() << std::endl;
        return 1;
    }
}

int cmd_keygen() {
    crypto::Key priv{}, pub{};
    crypto::generate_keypair_wg(priv, pub);
    std::cout << "Private key: " << crypto::base64_encode(priv) << std::endl;
    std::cout << "Public key:  " << crypto::base64_encode(pub)  << std::endl;
    return 0;
}

int cmd_connect(const std::string& name) {
    // Must run as root for TUN and route management
    if (geteuid() != 0) {
        std::cerr << "Error: 'connect' requires root privileges." << std::endl;
        std::cerr << "Please run with sudo." << std::endl;
        return 1;
    }

    config::VPNConfig cfg;
    try {
        cfg = config::load_config(name);
    } catch (std::exception& e) {
        std::cerr << "Error loading config '" << name << "': " << e.what() << std::endl;
        return 1;
    }

    // Print config summary
    std::cout << "Connecting with profile: " << cfg.name << std::endl;
    std::cout << "  Local address: " << cfg.address << std::endl;
    if (!cfg.dns.empty()) {
        std::cout << "  DNS: ";
        for (auto& d : cfg.dns) std::cout << d << " ";
        std::cout << std::endl;
    }
    if (!cfg.peers.empty()) {
        std::cout << "  Peer: " << cfg.peers[0].endpoint << std::endl;
        if (cfg.peers[0].obfs.enabled()) {
            std::cout << "  WG obfuscation: enabled (jc="
                      << cfg.peers[0].obfs.jc << ")" << std::endl;
        }
    }

    VPNClient client;
    g_vpn_client = &client;

    // Set up signal handling
    struct sigaction sa{};
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT,  &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);

    try {
        client.connect(cfg);
    } catch (std::exception& e) {
        std::cerr << "Connection failed: " << e.what() << std::endl;
        g_vpn_client = nullptr;
        return 1;
    }

    std::cout << "[MAIN] VPN connected. Press Ctrl+C to disconnect." << std::endl;

    // Wait until disconnected or interrupted
    while (!g_interrupted && client.state() != VPNState::Disconnected) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));

        // Print periodic status
        static int tick = 0;
        if (++tick % 60 == 0) {  // every 30s
            std::cout << "[STATUS] State=" << client.state_str()
                      << " Interface=" << client.interface_name()
                      << " Duration=" << client.connection_duration()
                      << std::endl;
        }
    }

    if (!g_interrupted) {
        // Exited due to disconnection
        client.disconnect();
    }

    g_vpn_client = nullptr;
    return 0;
}

int cmd_status() {
    // Check for a running process via lock file or similar mechanism
    // For simplicity, we just inform the user there's no daemon
    std::cout << "Status: Use 'connect <name>' to start the VPN (runs in foreground)." << std::endl;
    std::cout << "The VPN client runs in the foreground. Use Ctrl+C to disconnect." << std::endl;
    return 0;
}

int cmd_disconnect() {
    std::cout << "Disconnect: Send SIGTERM to the running veil process." << std::endl;
    std::cout << "Example: kill $(pgrep veil)" << std::endl;
    return 0;
}

// Find veil.app relative to this executable and open it.
static void launch_native_app() {
    char buf[4096] = {};
    uint32_t size = sizeof(buf);
    if (_NSGetExecutablePath(buf, &size) != 0) {
        std::cerr << "Cannot determine executable path\n";
        return;
    }
    std::string exe(buf);
    // exe = .../cmake-build-debug/veil
    // app = .../veil.app  (one level up from build dir)
    auto slash = exe.rfind('/');
    if (slash != std::string::npos) {
        std::string build_dir = exe.substr(0, slash);
        auto parent = build_dir.rfind('/');
        if (parent != std::string::npos) {
            std::string project = build_dir.substr(0, parent);
            std::string app = project + "/veil.app";
            ::system(("open \"" + app + "\"").c_str());
            return;
        }
    }
    // Fallback: look next to the binary
    ::system("open veil.app");
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        launch_native_app();
        return 0;
    }

    std::string command = argv[1];

    if (command == "add") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " add <config.json>" << std::endl;
            return 1;
        }
        return cmd_add(argv[2]);

    } else if (command == "list") {
        return cmd_list();

    } else if (command == "connect") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " connect <name>" << std::endl;
            return 1;
        }
        return cmd_connect(argv[2]);

    } else if (command == "disconnect") {
        return cmd_disconnect();

    } else if (command == "status") {
        return cmd_status();

    } else if (command == "remove") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " remove <name>" << std::endl;
            return 1;
        }
        return cmd_remove(argv[2]);

    } else if (command == "keygen") {
        return cmd_keygen();

    } else if (command == "--help" || command == "-h" || command == "help") {
        print_usage(argv[0]);
        return 0;

    } else {
        std::cerr << "Unknown command: " << command << std::endl;
        print_usage(argv[0]);
        return 1;
    }
}
