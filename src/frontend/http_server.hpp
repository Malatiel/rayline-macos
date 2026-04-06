#pragma once
#include <string>
#include <functional>
#include <map>
#include <sstream>
#include <thread>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <atomic>
#include <algorithm>
#include <sys/time.h>

struct HttpRequest {
    std::string method;
    std::string path;
    std::string body;
    std::map<std::string, std::string> headers;
};

struct HttpResponse {
    int         status       = 200;
    std::string content_type = "text/html; charset=utf-8";
    std::string body;

    static HttpResponse json(std::string b)     { return {200, "application/json", std::move(b)}; }
    static HttpResponse html(std::string b)     { return {200, "text/html; charset=utf-8", std::move(b)}; }
    static HttpResponse not_found()             { return {404, "text/plain", "Not Found"}; }
    static HttpResponse bad_request(std::string e) { return {400, "application/json",
        "{\"error\":\"" + e + "\"}"}; }
};

using Handler = std::function<HttpResponse(const HttpRequest&)>;

// Simple blocking HTTP/1.1 server; one thread per connection.
class HttpServer {
public:
    void route(const std::string& method, const std::string& path, Handler h) {
        routes_[method + " " + path] = std::move(h);
    }

    // Bind and start listening. Call before opening the browser so the port
    // is ready by the time the browser connects.
    bool prepare(int port) {
        srv_fd_ = ::socket(AF_INET, SOCK_STREAM, 0);
        if (srv_fd_ < 0) return false;
        int yes = 1;
        ::setsockopt(srv_fd_, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        sockaddr_in addr{};
        addr.sin_family      = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port        = htons((uint16_t)port);
        if (::bind(srv_fd_, (sockaddr*)&addr, sizeof(addr)) < 0) {
            ::close(srv_fd_); srv_fd_ = -1; return false;
        }
        ::listen(srv_fd_, 16);
        return true;
    }

    // Accept loop — blocks forever. Call after prepare().
    void run() {
        while (true) {
            int cli = ::accept(srv_fd_, nullptr, nullptr);
            if (cli < 0) continue;

            int previous = active_connections_.fetch_add(1);
            if (previous >= kMaxActiveConnections) {
                active_connections_.fetch_sub(1);
                ::close(cli);
                continue;
            }

            configure_client_socket(cli);
            std::thread([this, cli]{ handle(cli); }).detach();
        }
    }

    // Convenience: prepare + run in one call (original behaviour).
    void run(int port) { prepare(port); run(); }

private:
    std::map<std::string, Handler> routes_;
    int srv_fd_ = -1;
    std::atomic<int> active_connections_{0};
    static constexpr int kMaxActiveConnections = 64;

    static std::string recv_all(int fd) {
        std::string buf;
        char tmp[4096];
        // Read headers
        while (true) {
            ssize_t n = ::recv(fd, tmp, sizeof(tmp), 0);
            if (n <= 0) break;
            buf.append(tmp, (size_t)n);
            // Check if we have full headers
            auto hend = buf.find("\r\n\r\n");
            if (hend != std::string::npos) {
                // Check content-length
                auto cl_pos = buf.find("Content-Length: ");
                size_t cl = 0;
                if (cl_pos != std::string::npos) {
                    try { cl = std::stoul(buf.substr(cl_pos + 16)); }
                    catch (...) { cl = 0; }
                    // Reject unreasonably large bodies (1 MB max)
                    static const size_t MAX_BODY = 1 * 1024 * 1024;
                    if (cl > MAX_BODY) break;
                }
                size_t body_start = hend + 4;
                size_t body_have  = buf.size() - body_start;
                // Read remaining body
                while (body_have < cl) {
                    n = ::recv(fd, tmp, std::min(sizeof(tmp), cl - body_have), 0);
                    if (n <= 0) break;
                    buf.append(tmp, (size_t)n);
                    body_have += (size_t)n;
                }
                break;
            }
        }
        return buf;
    }

    static HttpRequest parse(const std::string& raw) {
        HttpRequest req;
        std::istringstream ss(raw);
        // Request line
        ss >> req.method >> req.path;
        std::string line;
        std::getline(ss, line); // consume rest of request line
        // Headers
        while (std::getline(ss, line) && line != "\r") {
            auto pos = line.find(": ");
            if (pos != std::string::npos) {
                std::string key = line.substr(0, pos);
                std::string val = line.substr(pos + 2);
                if (!val.empty() && val.back() == '\r') val.pop_back();
                req.headers[key] = val;
            }
        }
        // Body
        auto cl_it = req.headers.find("Content-Length");
        if (cl_it != req.headers.end()) {
            try {
                size_t cl = std::stoul(cl_it->second);
                auto body_start = raw.find("\r\n\r\n");
                if (body_start != std::string::npos)
                    req.body = raw.substr(body_start + 4, cl);
            } catch (...) {
                req.body.clear();
            }
        }
        return req;
    }

    void handle(int fd) {
        struct ConnectionGuard {
            int fd;
            std::atomic<int>& counter;

            ~ConnectionGuard() {
                counter.fetch_sub(1);
                ::close(fd);
            }
        } guard{fd, active_connections_};

        std::string raw = recv_all(fd);
        if (raw.empty()) { return; }

        HttpRequest req = parse(raw);

        HttpResponse resp;
        auto it = routes_.find(req.method + " " + req.path);
        if (it != routes_.end()) {
            resp = it->second(req);
        } else {
            resp = HttpResponse::not_found();
        }

        std::ostringstream out;
        out << "HTTP/1.1 " << resp.status << " OK\r\n"
            << "Content-Type: " << resp.content_type << "\r\n"
            << "Content-Length: " << resp.body.size() << "\r\n"
            << "Connection: close\r\n"
            << "Cache-Control: no-store\r\n"
            << "\r\n"
            << resp.body;
        std::string s = out.str();
        ::send(fd, s.data(), s.size(), 0);
    }

    void configure_client_socket(int fd) {
        struct timeval timeout {5, 0};
        ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    }
};
