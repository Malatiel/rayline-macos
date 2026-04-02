// Runs shared_test_cases.json against the C++ proxy parser.
// This ensures the C++ parser stays in sync with the Swift parser,
// since both test suites validate the same set of URIs and expectations.

#include "../src/proxy/proxy_parser.hpp"
#include "../src/crypto/mini_json.hpp"
#include <fstream>
#include <iostream>
#include <sstream>

static int g_failed = 0;
static int g_passed = 0;

static void check(bool cond, const std::string& test_name, const std::string& detail) {
    if (!cond) {
        std::cerr << "FAIL [" << test_name << "]: " << detail << "\n";
        ++g_failed;
    } else {
        ++g_passed;
    }
}

static std::string get_str(const json_ns::json& obj, const std::string& key) {
    if (!obj.contains(key)) return "";
    auto& v = obj.at(key);
    if (v.is_string()) return v.get<std::string>();
    return "";
}

static int get_int(const json_ns::json& obj, const std::string& key) {
    if (!obj.contains(key)) return -1;
    auto& v = obj.at(key);
    if (v.is_int()) return v.get<int>();
    return -1;
}

static bool get_bool(const json_ns::json& obj, const std::string& key) {
    if (!obj.contains(key)) return false;
    auto& v = obj.at(key);
    if (v.is_bool()) return v.get<bool>();
    return false;
}

int main(int argc, char* argv[]) {
    // Find the JSON file relative to the executable or via argument
    std::string json_path = "Tests/shared_test_cases.json";
    if (argc > 1) json_path = argv[1];

    std::ifstream ifs(json_path);
    if (!ifs.is_open()) {
        std::cerr << "Cannot open " << json_path << "\n";
        return 1;
    }
    std::ostringstream ss;
    ss << ifs.rdbuf();
    std::string json_str = ss.str();

    auto root = json_ns::json::parse(json_str);
    auto& tests = root.at("parse_tests");

    for (auto& tc : tests) {
        std::string name = get_str(tc, "name");
        std::string uri = get_str(tc, "uri");
        auto& expect = tc.at("expect");

        auto p = proxy::parse_uri(uri);

        bool expect_valid = get_bool(expect, "valid");
        check(p.valid() == expect_valid, name, "valid mismatch: got " +
              std::string(p.valid() ? "true" : "false"));

        if (!expect_valid) continue;  // nothing else to check for invalid URIs

        if (expect.contains("protocol")) {
            std::string exp = get_str(expect, "protocol");
            check(p.protocol_name() == exp, name,
                  "protocol: expected \"" + exp + "\" got \"" + p.protocol_name() + "\"");
        }
        if (expect.contains("server")) {
            std::string exp = get_str(expect, "server");
            check(p.server == exp, name,
                  "server: expected \"" + exp + "\" got \"" + p.server + "\"");
        }
        if (expect.contains("port")) {
            int exp = get_int(expect, "port");
            check(p.port == exp, name,
                  "port: expected " + std::to_string(exp) + " got " + std::to_string(p.port));
        }
        if (expect.contains("uuid")) {
            std::string exp = get_str(expect, "uuid");
            check(p.uuid == exp, name,
                  "uuid: expected \"" + exp + "\" got \"" + p.uuid + "\"");
        }
        if (expect.contains("security")) {
            std::string exp = get_str(expect, "security");
            check(p.security == exp, name,
                  "security: expected \"" + exp + "\" got \"" + p.security + "\"");
        }
        if (expect.contains("network")) {
            std::string exp = get_str(expect, "network");
            check(p.network == exp, name,
                  "network: expected \"" + exp + "\" got \"" + p.network + "\"");
        }
        if (expect.contains("sni")) {
            std::string exp = get_str(expect, "sni");
            check(p.sni == exp, name,
                  "sni: expected \"" + exp + "\" got \"" + p.sni + "\"");
        }
        if (expect.contains("host")) {
            std::string exp = get_str(expect, "host");
            check(p.host == exp, name,
                  "host: expected \"" + exp + "\" got \"" + p.host + "\"");
        }
        if (expect.contains("path")) {
            std::string exp = get_str(expect, "path");
            check(p.path == exp, name,
                  "path: expected \"" + exp + "\" got \"" + p.path + "\"");
        }
        if (expect.contains("name")) {
            std::string exp = get_str(expect, "name");
            check(p.name == exp, name,
                  "name: expected \"" + exp + "\" got \"" + p.name + "\"");
        }
        if (expect.contains("method")) {
            std::string exp = get_str(expect, "method");
            check(p.method == exp, name,
                  "method: expected \"" + exp + "\" got \"" + p.method + "\"");
        }
        if (expect.contains("pbk")) {
            std::string exp = get_str(expect, "pbk");
            check(p.pbk == exp, name,
                  "pbk: expected \"" + exp + "\" got \"" + p.pbk + "\"");
        }
        if (expect.contains("short_id")) {
            std::string exp = get_str(expect, "short_id");
            check(p.short_id == exp, name,
                  "short_id: expected \"" + exp + "\" got \"" + p.short_id + "\"");
        }
        if (expect.contains("fp")) {
            std::string exp = get_str(expect, "fp");
            check(p.fp == exp, name,
                  "fp: expected \"" + exp + "\" got \"" + p.fp + "\"");
        }
        if (expect.contains("allow_insecure")) {
            bool exp = get_bool(expect, "allow_insecure");
            check(p.allow_insecure == exp, name,
                  "allow_insecure: expected " + std::string(exp ? "true" : "false"));
        }
    }

    std::cout << g_passed << " checks passed";
    if (g_failed > 0) {
        std::cout << ", " << g_failed << " FAILED";
    }
    std::cout << " (shared_test_cases.json)\n";
    return g_failed > 0 ? 1 : 0;
}
