#include "config.hpp"
#include <fstream>
#include <sstream>
#include <filesystem>
#include <stdexcept>
#include <iostream>

namespace config {

namespace fs = std::filesystem;

// Get the config directory (~/.veil/wireguard/)
std::string get_config_dir() {
    const char* home = getenv("HOME");
    if (!home) throw std::runtime_error("HOME environment variable not set");
    return std::string(home) + "/.veil/wireguard";
}

// Ensure config directory exists
void ensure_config_dir() {
    auto dir = get_config_dir();
    if (!fs::exists(dir)) {
        fs::create_directories(dir);
    }
}

// Get path for a named config
std::string config_path(const std::string& name) {
    return get_config_dir() + "/" + name + ".json";
}

// Save a config to disk
void save_config(const VPNConfig& cfg) {
    ensure_config_dir();
    auto path = config_path(cfg.name);
    std::ofstream f(path);
    if (!f.is_open()) {
        throw std::runtime_error("Cannot open config file for writing: " + path);
    }
    f << config_to_json(cfg).dump(2);
    f.close();
    std::cout << "Config '" << cfg.name << "' saved to " << path << std::endl;
}

// Load a named config from disk
VPNConfig load_config(const std::string& name) {
    auto path = config_path(name);
    std::ifstream f(path);
    if (!f.is_open()) {
        throw std::runtime_error("Config not found: " + name + " (looked in " + path + ")");
    }
    std::stringstream ss;
    ss << f.rdbuf();
    auto j = json_ns::value::parse(ss.str());
    return config_from_json(j);
}

// Load config from an arbitrary path
VPNConfig load_config_from_file(const std::string& filepath) {
    std::ifstream f(filepath);
    if (!f.is_open()) {
        throw std::runtime_error("Cannot open config file: " + filepath);
    }
    std::stringstream ss;
    ss << f.rdbuf();
    auto j = json_ns::value::parse(ss.str());
    return config_from_json(j);
}

// List all configs
std::vector<std::string> list_configs() {
    ensure_config_dir();
    std::vector<std::string> names;
    auto dir = get_config_dir();
    for (auto& entry : fs::directory_iterator(dir)) {
        if (entry.path().extension() == ".json") {
            names.push_back(entry.path().stem().string());
        }
    }
    return names;
}

// Remove a config
void remove_config(const std::string& name) {
    auto path = config_path(name);
    if (!fs::exists(path)) {
        throw std::runtime_error("Config not found: " + name);
    }
    fs::remove(path);
    std::cout << "Config '" << name << "' removed." << std::endl;
}

// Check if a config exists
bool config_exists(const std::string& name) {
    return fs::exists(config_path(name));
}

} // namespace config
