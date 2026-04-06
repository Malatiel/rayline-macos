#include "../src/config/config.hpp"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

static int g_failed = 0;
static std::filesystem::path g_test_home;

#define CHECK(expr) do { \
    if (!(expr)) { \
        std::cerr << "FAIL [" << __LINE__ << "]: " << #expr << "\n"; \
        ++g_failed; \
    } \
} while(0)

static config::VPNConfig sample_config(std::string name) {
    config::VPNConfig cfg;
    cfg.name = std::move(name);
    cfg.address = "10.0.0.2/24";
    cfg.dns = {"1.1.1.1"};
    cfg.mtu = 1420;
    return cfg;
}

static void test_rejects_path_traversal() {
    bool thrown = false;
    try {
        (void)config::config_path("../escape");
    } catch (const std::exception&) {
        thrown = true;
    }
    CHECK(thrown);
}

static void test_rejects_slashes_in_name() {
    bool thrown = false;
    try {
        (void)config::config_path("nested/profile");
    } catch (const std::exception&) {
        thrown = true;
    }
    CHECK(thrown);
}

static void test_accepts_normal_name() {
    const std::string path = config::config_path("Home VPN-1.0");
    CHECK(path.find("Home VPN-1.0.json") != std::string::npos);
}

static void test_saved_file_permissions_are_0600() {
    const std::string name = "Permission Test";
    config::save_config(sample_config(name));

    struct stat st{};
    CHECK(stat(config::config_path(name).c_str(), &st) == 0);
    CHECK((st.st_mode & 0777) == 0600);
}

int main() {
    g_test_home = std::filesystem::temp_directory_path() / ("veil-config-test-" + std::to_string(::getpid()));
    std::filesystem::create_directories(g_test_home);
    setenv("HOME", g_test_home.c_str(), 1);

    test_rejects_path_traversal();
    test_rejects_slashes_in_name();
    test_accepts_normal_name();
    test_saved_file_permissions_are_0600();

    std::error_code ec;
    std::filesystem::remove_all(g_test_home, ec);

    if (g_failed == 0) {
        std::cout << "All config tests passed\n";
        return 0;
    }

    std::cout << g_failed << " config tests failed\n";
    return 1;
}
