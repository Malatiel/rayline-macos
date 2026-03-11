//  veil-gui — local HTTP server + browser UI for VLESS VPN management
//  Opens http://127.0.0.1:18080 automatically in the default browser.
//  Requires sing-box (https://github.com/SagerNet/sing-box) to be installed.

#include "gui_server.hpp"
#include "http_server.hpp"
#include "../proxy/proxy_parser.hpp"

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <atomic>
#include <mutex>
#include <deque>
#include <vector>
#include <chrono>
#include <thread>
#include <cstring>
#include <cmath>

#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <signal.h>
#include <mach-o/dyld.h>

// ── Globals ────────────────────────────────────────────────────────────────

static std::mutex          g_mu;
static pid_t               g_child_pid  = -1;
static std::string         g_state      = "disconnected";  // disconnected|connecting|connected|error
static std::string         g_last_error;
static std::string         g_current_url;
static std::string         g_profile_name;
static std::string         g_server_info;
static std::deque<std::string>  g_log;

static const std::string   SOCKS_HOST = "127.0.0.1";
static const int           SOCKS_PORT = 10808;
static const std::string   CONFIG_PATH = "/tmp/veil_singbox.json";
static const int           GUI_PORT   = 18080;

// ── Ping stats ──────────────────────────────────────────────────────────────
static std::string         g_ping_host;           // VPN server hostname / IP
static uint16_t            g_ping_port{443};       // VPN server port
static std::atomic<int>    g_ping_ms{-1};          // last RTT ms, -1 = no reply
static std::atomic<long>   g_packets_sent{0};
static std::atomic<long>   g_packets_recv{0};
static std::atomic<bool>   g_ping_stop{false};
static std::thread         g_ping_thread;

// ── Helpers ────────────────────────────────────────────────────────────────

static void push_log(const std::string& msg) {
    auto now = std::chrono::system_clock::now();
    std::time_t t = std::chrono::system_clock::to_time_t(now);
    char ts[16];
    std::strftime(ts, sizeof(ts), "%H:%M:%S", std::localtime(&t));
    std::lock_guard<std::mutex> lk(g_mu);
    g_log.push_back(std::string(ts) + " " + msg);
    if (g_log.size() > 200) g_log.pop_front();
}

static std::string jesc(const std::string& s) {
    std::string o;
    for (unsigned char c : s) {
        if      (c == '"')  o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else if (c == '\r') o += "\\r";
        else if (c == '\t') o += "\\t";
        else if (c < 0x20) {
            char buf[8];
            std::snprintf(buf, sizeof(buf), "\\u%04x", c);
            o += buf;
        }
        else o += (char)c;
    }
    return o;
}

static std::string find_singbox() {
    // Check next to the current executable (bundled app)
    char exec_buf[4096] = {};
    uint32_t exec_size = sizeof(exec_buf);
    if (_NSGetExecutablePath(exec_buf, &exec_size) == 0) {
        std::string exe(exec_buf);
        auto slash = exe.rfind('/');
        if (slash != std::string::npos) {
            std::string bundled = exe.substr(0, slash + 1) + "sing-box";
            if (::access(bundled.c_str(), X_OK) == 0) return bundled;
        }
    }

    const char* paths[] = {
        "/opt/homebrew/bin/sing-box",
        "/usr/local/bin/sing-box",
        "/usr/bin/sing-box",
        nullptr
    };
    for (int i = 0; paths[i]; ++i) {
        if (::access(paths[i], X_OK) == 0) return paths[i];
    }
    // Try PATH via which
    FILE* f = ::popen("which sing-box 2>/dev/null", "r");
    if (f) {
        char buf[256] = {};
        if (std::fgets(buf, sizeof(buf), f)) {
            std::string p(buf);
            while (!p.empty() && (p.back() == '\n' || p.back() == '\r' || p.back() == ' '))
                p.pop_back();
            ::pclose(f);
            if (!p.empty() && ::access(p.c_str(), X_OK) == 0) return p;
        }
        ::pclose(f);
    }
    return "";
}

// Measure TCP handshake RTT to host:port.
// Returns milliseconds on success, -1 on timeout / error.
// Uses non-blocking connect + select so we don't block the thread for long.
static int tcp_rtt_ms(const std::string& host, uint16_t port) {
    char port_str[8];
    std::snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);

    struct addrinfo hints{};
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo* res = nullptr;
    if (::getaddrinfo(host.c_str(), port_str, &hints, &res) != 0 || !res)
        return -1;

    int fd = ::socket(res->ai_family, SOCK_STREAM, 0);
    if (fd < 0) { ::freeaddrinfo(res); return -1; }

    // Switch to non-blocking so connect() returns immediately
    ::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL, 0) | O_NONBLOCK);

    auto t0 = std::chrono::steady_clock::now();
    ::connect(fd, res->ai_addr, res->ai_addrlen);  // EINPROGRESS is expected
    ::freeaddrinfo(res);

    // Wait up to 2 s for the socket to become writable (= TCP SYN-ACK received)
    fd_set wset;
    FD_ZERO(&wset);
    FD_SET(fd, &wset);
    struct timeval tv{2, 0};
    int sel = ::select(fd + 1, nullptr, &wset, nullptr, &tv);

    int rtt = -1;
    if (sel > 0) {
        // Check whether connect actually succeeded
        int err = 0;
        socklen_t elen = sizeof(err);
        ::getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &elen);
        if (err == 0) {
            auto t1 = std::chrono::steady_clock::now();
            rtt = (int)std::chrono::duration_cast<
                            std::chrono::milliseconds>(t1 - t0).count();
        }
    }

    ::close(fd);
    return rtt;
}

// Background thread: measures TCP RTT to the VPN server every 3 s.
// Works even when the server blocks ICMP.
static void ping_worker() {
    while (!g_ping_stop.load()) {
        std::string host;
        uint16_t    port;
        {
            std::lock_guard<std::mutex> lk(g_mu);
            host = g_ping_host;
            port = g_ping_port;
        }

        if (!host.empty()) {
            g_packets_sent.fetch_add(1);
            int rtt = tcp_rtt_ms(host, port);
            g_ping_ms.store(rtt);
            if (rtt >= 0) g_packets_recv.fetch_add(1);
        }

        // Sleep 3 s in 100 ms steps so the stop flag is noticed quickly
        for (int i = 0; i < 30 && !g_ping_stop.load(); ++i)
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}

// Returns true if the network service name is safe to embed in a double-quoted
// shell argument (no double-quote, backtick, dollar sign or control chars).
static bool is_safe_service_name(const std::string& s) {
    if (s.empty()) return false;
    for (unsigned char c : s) {
        if (c == '"' || c == '\'' || c == '`' || c == '$' ||
            c == '\\' || c < 0x20)
            return false;
    }
    return true;
}

static void set_system_proxy(bool enable) {
    // Collect all enabled (non-disabled) network services
    std::vector<std::string> services;
    FILE* f = ::popen("networksetup -listallnetworkservices 2>/dev/null", "r");
    if (f) {
        char buf[256];
        bool skip_header = true;
        while (std::fgets(buf, sizeof(buf), f)) {
            if (skip_header) { skip_header = false; continue; } // first line is a description
            std::string line(buf);
            while (!line.empty() && (line.back()=='\n'||line.back()=='\r'||line.back()==' '))
                line.pop_back();
            if (!line.empty() && line.front() != '*')  // '*' prefix = disabled service
                services.push_back(line);
        }
        ::pclose(f);
    }
    if (services.empty()) services.push_back("Wi-Fi");

    for (const auto& dev : services) {
        if (!is_safe_service_name(dev)) {
            push_log("Skipping service with unsafe name: " + dev);
            continue;
        }
        std::string cmd;
        if (enable) {
            cmd = std::string("networksetup -setsocksfirewallproxy \"") + dev + "\" " +
                  SOCKS_HOST + " " + std::to_string(SOCKS_PORT) + " 2>/dev/null && " +
                  "networksetup -setsocksfirewallproxystate \"" + dev + "\" on 2>/dev/null";
        } else {
            cmd = std::string("networksetup -setsocksfirewallproxystate \"") +
                  dev + "\" off 2>/dev/null";
        }
        ::system(cmd.c_str());
        push_log(std::string(enable ? "Proxy enabled: " : "Proxy disabled: ") + dev);
    }
}

// ── Connect / Disconnect ────────────────────────────────────────────────────

static bool do_connect(const std::string& url) {
    // Parse VLESS URL
    proxy::ProxyConfig proxy;
    try {
        proxy = proxy::parse_uri(url);
    } catch (std::exception& e) {
        std::lock_guard<std::mutex> lk(g_mu);
        g_last_error = e.what();
        g_state = "error";
        return false;
    }
    if (!proxy.valid()) {
        std::lock_guard<std::mutex> lk(g_mu);
        g_last_error = "Invalid or unsupported proxy URL";
        g_state = "error";
        return false;
    }

    // Find sing-box
    std::string sb = find_singbox();
    if (sb.empty()) {
        std::lock_guard<std::mutex> lk(g_mu);
        g_last_error = "sing-box not found. Install: brew install sing-box";
        g_state = "error";
        push_log("ERROR: " + g_last_error);
        return false;
    }

    // Generate config — write with owner-only permissions (0600) so other
    // local users cannot read VPN credentials stored in the temp file.
    std::string cfg_json = proxy.to_sing_box_config();
    {
        int cfg_fd = ::open(CONFIG_PATH.c_str(),
                            O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
        if (cfg_fd < 0) {
            std::lock_guard<std::mutex> lk(g_mu);
            g_last_error = "Cannot write config to " + CONFIG_PATH;
            g_state = "error";
            return false;
        }
        const char* ptr = cfg_json.c_str();
        size_t rem = cfg_json.size();
        while (rem > 0) {
            ssize_t w = ::write(cfg_fd, ptr, rem);
            if (w < 0) {
                ::close(cfg_fd);
                std::lock_guard<std::mutex> lk(g_mu);
                g_last_error = "Write error for config " + CONFIG_PATH;
                g_state = "error";
                return false;
            }
            ptr += w; rem -= (size_t)w;
        }
        ::close(cfg_fd);
    }

    push_log("Config written to " + CONFIG_PATH);
    push_log("Starting sing-box: " + sb);

    // Fork sing-box
    pid_t pid = ::fork();
    if (pid < 0) {
        std::lock_guard<std::mutex> lk(g_mu);
        g_last_error = "fork() failed";
        g_state = "error";
        return false;
    }

    if (pid == 0) {
        // Child: redirect stdout/stderr to /tmp/veil_singbox.log
        int log_fd = ::open("/tmp/veil_singbox.log",
                            O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
        if (log_fd >= 0) {
            ::dup2(log_fd, STDOUT_FILENO);
            ::dup2(log_fd, STDERR_FILENO);
            ::close(log_fd);
        }
        ::execl(sb.c_str(), "sing-box", "run", "-c", CONFIG_PATH.c_str(), nullptr);
        ::_exit(127);
    }

    {
        std::lock_guard<std::mutex> lk(g_mu);
        g_child_pid   = pid;
        g_current_url = url;
        g_profile_name = proxy.name;
        g_server_info  = proxy.protocol_name() + " → " + proxy.server + ":" + std::to_string(proxy.port);
        g_state = "connecting";
        g_last_error.clear();
    }

    push_log("sing-box PID=" + std::to_string(pid));

    // Wait ~1.5s then check if still alive
    std::this_thread::sleep_for(std::chrono::milliseconds(1500));
    int wstatus = 0;
    pid_t r = ::waitpid(pid, &wstatus, WNOHANG);
    if (r == pid) {
        // Process exited already → error
        std::lock_guard<std::mutex> lk(g_mu);
        g_child_pid = -1;
        g_state = "error";
        g_last_error = "sing-box exited immediately (check /tmp/veil_singbox.log)";
        push_log("ERROR: " + g_last_error);
        return false;
    }

    {
        std::lock_guard<std::mutex> lk(g_mu);
        g_state = "connected";
        g_ping_host = proxy.server;
        g_ping_port = proxy.port;
    }

    push_log("Connected! SOCKS5 on " + SOCKS_HOST + ":" + std::to_string(SOCKS_PORT));

    // Start ping monitoring thread
    g_packets_sent.store(0);
    g_packets_recv.store(0);
    g_ping_ms.store(-1);
    g_ping_stop.store(false);
    if (g_ping_thread.joinable()) g_ping_thread.join();
    g_ping_thread = std::thread(ping_worker);

    // Set macOS system proxy
    set_system_proxy(true);

    return true;
}

static void do_disconnect() {
    // Stop ping thread first
    g_ping_stop.store(true);
    if (g_ping_thread.joinable()) g_ping_thread.join();
    g_ping_ms.store(-1);
    g_packets_sent.store(0);
    g_packets_recv.store(0);
    {
        std::lock_guard<std::mutex> lk(g_mu);
        g_ping_host.clear();
    }

    pid_t pid = -1;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        pid = g_child_pid;
        g_state = "disconnected";
        g_child_pid = -1;
    }

    if (pid > 0) {
        ::kill(pid, SIGTERM);
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        int st = 0;
        if (::waitpid(pid, &st, WNOHANG) == 0) {
            ::kill(pid, SIGKILL);
            ::waitpid(pid, &st, 0);
        }
        push_log("sing-box PID=" + std::to_string(pid) + " stopped");
        set_system_proxy(false);
        ::unlink(CONFIG_PATH.c_str());
    }
}

// ── Embedded HTML UI ────────────────────────────────────────────────────────

static const char* HTML = R"HTML(<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Veil</title>
<style>
  :root {
    --bg:     #0d0d14;
    --card:   #16161f;
    --border: #2a2a3a;
    --text:   #e0e0f0;
    --muted:  #7070a0;
    --accent: #7c5cfc;
    --green:  #22c55e;
    --red:    #ef4444;
    --yellow: #eab308;
    --mono:   'JetBrains Mono', 'Fira Code', monospace;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
    min-height: 100vh;
    padding: 2rem 1rem;
  }
  .container { max-width: 720px; margin: 0 auto; }

  h1 {
    font-size: 1.6rem;
    font-weight: 700;
    letter-spacing: -0.03em;
    margin-bottom: 0.3rem;
  }
  h1 span { color: var(--accent); }
  .subtitle { color: var(--muted); font-size: 0.9rem; margin-bottom: 2rem; }

  .card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 1rem;
  }
  .card-title {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    margin-bottom: 1rem;
  }

  textarea {
    width: 100%;
    height: 96px;
    background: #0d0d14;
    border: 1px solid var(--border);
    border-radius: 8px;
    color: var(--text);
    font-family: var(--mono);
    font-size: 0.78rem;
    padding: 0.75rem;
    resize: vertical;
    outline: none;
    transition: border-color 0.2s;
  }
  textarea:focus { border-color: var(--accent); }
  textarea::placeholder { color: var(--muted); }

  .btn-row { display: flex; gap: 0.75rem; margin-top: 1rem; }

  button {
    flex: 1;
    padding: 0.75rem 1rem;
    border: none;
    border-radius: 8px;
    font-size: 0.9rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s, transform 0.1s;
    letter-spacing: 0.01em;
  }
  button:active { transform: scale(0.97); }
  button:disabled { opacity: 0.4; cursor: not-allowed; }
  .btn-connect    { background: var(--accent); color: #fff; }
  .btn-disconnect { background: #2a2a3a; color: var(--red); border: 1px solid var(--red); }
  .btn-parse      { background: #1f1f2e; color: var(--text); border: 1px solid var(--border); flex: 0 0 auto; }

  /* Status badge */
  .status-row { display: flex; align-items: center; gap: 0.75rem; }
  .dot {
    width: 10px; height: 10px; border-radius: 50%;
    background: var(--muted);
    box-shadow: 0 0 0 0 transparent;
    transition: background 0.3s, box-shadow 0.3s;
  }
  .dot.connected  { background: var(--green);  box-shadow: 0 0 8px var(--green); }
  .dot.connecting { background: var(--yellow); animation: pulse 1s infinite; }
  .dot.error      { background: var(--red); }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50%       { opacity: 0.3; }
  }

  .state-text { font-size: 1rem; font-weight: 600; }
  .state-text.connected  { color: var(--green); }
  .state-text.connecting { color: var(--yellow); }
  .state-text.error      { color: var(--red); }

  /* Info grid */
  .info-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.75rem;
    margin-top: 1rem;
  }
  .info-item { background: #0d0d14; border-radius: 8px; padding: 0.75rem; }
  .info-label { font-size: 0.7rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; }
  .info-value { font-size: 0.85rem; font-family: var(--mono); margin-top: 0.2rem; word-break: break-all; }

  /* Error box */
  .error-box {
    background: rgba(239,68,68,0.1);
    border: 1px solid rgba(239,68,68,0.4);
    border-radius: 8px;
    padding: 0.75rem 1rem;
    color: var(--red);
    font-size: 0.85rem;
    margin-top: 1rem;
    display: none;
  }

  /* Log */
  .log-area {
    background: #0a0a10;
    border-radius: 8px;
    height: 180px;
    overflow-y: auto;
    padding: 0.75rem;
    font-family: var(--mono);
    font-size: 0.75rem;
    color: #9090c0;
    border: 1px solid var(--border);
  }
  .log-area p { margin-bottom: 0.2rem; }
  .log-area p:last-child { margin-bottom: 0; }

  /* Parsed info preview */
  #preview {
    background: #0a0a10;
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.75rem;
    font-family: var(--mono);
    font-size: 0.78rem;
    color: var(--text);
    margin-top: 1rem;
    display: none;
    white-space: pre;
    overflow-x: auto;
  }
</style>
</head>
<body>
<div class="container">

  <h1>Veil</h1>
  <p class="subtitle">VLESS · VMess · Shadowsocks · Trojan</p>

  <!-- Status -->
  <div class="card">
    <div class="card-title">Статус подключения</div>
    <div class="status-row">
      <div class="dot" id="dot"></div>
      <span class="state-text" id="stateText">Отключено</span>
    </div>
    <div class="info-grid" id="infoGrid" style="display:none">
      <div class="info-item">
        <div class="info-label">Профиль</div>
        <div class="info-value" id="iProfile">—</div>
      </div>
      <div class="info-item">
        <div class="info-label">Сервер</div>
        <div class="info-value" id="iServer">—</div>
      </div>
      <div class="info-item">
        <div class="info-label">SOCKS5 прокси</div>
        <div class="info-value" id="iSocks">—</div>
      </div>
      <div class="info-item">
        <div class="info-label">PID</div>
        <div class="info-value" id="iPid">—</div>
      </div>
      <div class="info-item">
        <div class="info-label">Задержка (TCP)</div>
        <div class="info-value" id="iPing">—</div>
      </div>
      <div class="info-item">
        <div class="info-label">Потеря пакетов</div>
        <div class="info-value" id="iLoss">—</div>
      </div>
      <div class="info-item">
        <div class="info-label">Отправлено</div>
        <div class="info-value" id="iSent">—</div>
      </div>
      <div class="info-item">
        <div class="info-label">Получено</div>
        <div class="info-value" id="iRecv">—</div>
      </div>
    </div>
    <div class="error-box" id="errorBox"></div>
  </div>

  <!-- Import -->
  <div class="card">
    <div class="card-title">Импорт ссылки</div>
    <textarea id="urlInput" placeholder="vless://uuid@host:port?...  или  vmess://...  или  ss://..."></textarea>
    <div id="preview"></div>
    <div class="btn-row">
      <button class="btn-parse" onclick="parseCfg()">Проверить</button>
      <button class="btn-connect" id="btnConnect" onclick="connect()">Подключить</button>
      <button class="btn-disconnect" id="btnDisconnect" onclick="disconnect()" style="display:none">Отключить</button>
    </div>
  </div>

  <!-- Log -->
  <div class="card">
    <div class="card-title">Лог</div>
    <div class="log-area" id="logArea"></div>
  </div>

</div>

<script>
let pollTimer = null;

function apiFetch(path, body) {
  const opts = body
    ? { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) }
    : { method: 'GET' };
  return fetch(path, opts).then(r => r.json());
}

function stateLabel(s) {
  return { connected:'Подключено', connecting:'Подключение…', disconnected:'Отключено', error:'Ошибка' }[s] || s;
}

function applyStatus(data) {
  const dot       = document.getElementById('dot');
  const stateText = document.getElementById('stateText');
  const grid      = document.getElementById('infoGrid');
  const errBox    = document.getElementById('errorBox');
  const btnC      = document.getElementById('btnConnect');
  const btnD      = document.getElementById('btnDisconnect');

  dot.className       = 'dot ' + data.state;
  stateText.className = 'state-text ' + data.state;
  stateText.textContent = stateLabel(data.state);

  if (data.state === 'connected' || data.state === 'connecting') {
    grid.style.display = 'grid';
    document.getElementById('iProfile').textContent = data.profile || '—';
    document.getElementById('iServer').textContent  = data.server  || '—';
    document.getElementById('iSocks').textContent   = data.socks   || '—';
    document.getElementById('iPid').textContent     = data.pid     || '—';

    // Ping
    const ping = document.getElementById('iPing');
    if (data.ping_ms != null && data.ping_ms >= 0) {
      ping.textContent = data.ping_ms + ' мс';
      ping.style.color = data.ping_ms < 100 ? 'var(--green)'
                       : data.ping_ms < 250 ? 'var(--yellow)'
                       : 'var(--red)';
    } else {
      ping.textContent = '…';
      ping.style.color = '';
    }

    // Packet loss %
    const sent = data.pkts_sent || 0;
    const recv = data.pkts_recv || 0;
    const lossEl = document.getElementById('iLoss');
    if (sent > 0) {
      const loss = Math.round((sent - recv) / sent * 100);
      lossEl.textContent = loss + ' %';
      lossEl.style.color = loss === 0 ? 'var(--green)'
                         : loss < 10  ? 'var(--yellow)'
                         : 'var(--red)';
    } else {
      lossEl.textContent = '—';
      lossEl.style.color = '';
    }

    document.getElementById('iSent').textContent = sent || '—';
    document.getElementById('iRecv').textContent = recv || '—';

    btnC.style.display = 'none';
    btnD.style.display = '';
  } else {
    grid.style.display = 'none';
    btnC.style.display = '';
    btnD.style.display = 'none';
  }

  if (data.error) {
    errBox.style.display = '';
    errBox.textContent   = data.error;
  } else {
    errBox.style.display = 'none';
  }

  if (data.log && data.log.length) {
    const area = document.getElementById('logArea');
    area.innerHTML = data.log.map(l => '<p>' + escHtml(l) + '</p>').join('');
    area.scrollTop = area.scrollHeight;
  }
}

function escHtml(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function startPoll() {
  if (pollTimer) return;
  pollTimer = setInterval(poll, 2000);
}

function poll() {
  apiFetch('/api/status').then(applyStatus).catch(() => {});
}

function parseCfg() {
  const url = document.getElementById('urlInput').value.trim();
  const pre = document.getElementById('preview');
  if (!url) {
    pre.style.display = '';
    pre.textContent = '⚠ Вставьте ссылку в поле выше';
    return;
  }
  pre.style.display = '';
  pre.textContent = '⏳ Проверка…';
  apiFetch('/api/parse', {url}).then(data => {
    if (data.error) {
      pre.textContent = '❌ ' + data.error;
    } else {
      pre.textContent =
        'Протокол : ' + data.protocol + '\n' +
        'Имя      : ' + data.name     + '\n' +
        'Сервер   : ' + data.server   + ':' + data.port + '\n' +
        'Безопасн.: ' + data.security + '\n' +
        (data.sni  ? 'SNI      : ' + data.sni  + '\n' : '') +
        (data.flow ? 'Flow     : ' + data.flow + '\n' : '') +
        '✅ Ссылка корректна';
    }
  }).catch(err => {
    pre.textContent = '❌ Нет связи с сервером: ' + (err.message || err);
  });
}

function showNetworkError(msg) {
  const errBox = document.getElementById('errorBox');
  errBox.style.display = '';
  errBox.textContent = '⚠ ' + msg;
}

function connect() {
  const url = document.getElementById('urlInput').value.trim();
  if (!url) { alert('Вставьте VLESS/VMess/SS ссылку'); return; }
  document.getElementById('btnConnect').disabled = true;
  apiFetch('/api/connect', {url}).then(data => {
    applyStatus(data);
    document.getElementById('btnConnect').disabled = false;
  }).catch(err => {
    showNetworkError('Нет связи с сервером: ' + (err.message || err));
    document.getElementById('btnConnect').disabled = false;
  });
}

function disconnect() {
  document.getElementById('btnDisconnect').disabled = true;
  apiFetch('/api/disconnect', {}).then(data => {
    applyStatus(data);
    document.getElementById('btnDisconnect').disabled = false;
  }).catch(err => {
    showNetworkError('Нет связи с сервером: ' + (err.message || err));
    document.getElementById('btnDisconnect').disabled = false;
  });
}

// Prefill with the bundled URL
window.addEventListener('DOMContentLoaded', () => {
  const bundled = document.body.dataset.bundleUrl || '';
  if (bundled) document.getElementById('urlInput').value = bundled;
  poll();
  startPoll();
});
</script>
</body>
</html>
)HTML";

// ── JSON helpers ────────────────────────────────────────────────────────────

static std::string status_json() {
    // Read atomic ping stats outside the mutex
    int  ping_ms    = g_ping_ms.load();
    long pkts_sent  = g_packets_sent.load();
    long pkts_recv  = g_packets_recv.load();

    std::lock_guard<std::mutex> lk(g_mu);
    std::ostringstream j;
    j << "{";
    j << "\"state\":\"" << jesc(g_state) << "\"";
    j << ",\"profile\":\"" << jesc(g_profile_name) << "\"";
    j << ",\"server\":\"" << jesc(g_server_info) << "\"";
    j << ",\"socks\":\"" << SOCKS_HOST << ":" << SOCKS_PORT << "\"";
    j << ",\"pid\":" << (g_child_pid > 0 ? std::to_string(g_child_pid) : "null");
    j << ",\"ping_ms\":" << ping_ms;
    j << ",\"pkts_sent\":" << pkts_sent;
    j << ",\"pkts_recv\":" << pkts_recv;
    j << ",\"error\":\"" << jesc(g_last_error) << "\"";
    j << ",\"log\":[";
    for (size_t i = 0; i < g_log.size(); ++i) {
        j << "\"" << jesc(g_log[i]) << "\"";
        if (i + 1 < g_log.size()) j << ",";
    }
    j << "]}";
    return j.str();
}

// Extract a JSON string field from a simple flat JSON body
static std::string json_str(const std::string& body, const std::string& key) {
    std::string pat = "\"" + key + "\"";
    auto pos = body.find(pat);
    if (pos == std::string::npos) return "";
    pos += pat.size();
    // skip : and whitespace
    while (pos < body.size() && (body[pos] == ' ' || body[pos] == ':')) ++pos;
    if (pos >= body.size() || body[pos] != '"') return "";
    ++pos;
    std::string val;
    while (pos < body.size() && body[pos] != '"') {
        if (body[pos] == '\\' && pos + 1 < body.size()) { ++pos; val += body[pos]; }
        else val += body[pos];
        ++pos;
    }
    return val;
}

// ── Signal handler ──────────────────────────────────────────────────────────

static void on_signal(int) {
    do_disconnect();
    ::exit(0);
}

// ── run_gui() — public entry point ──────────────────────────────────────────

void run_gui(const std::string& bundled_url) {
    ::signal(SIGINT,  on_signal);
    ::signal(SIGTERM, on_signal);
    ::signal(SIGCHLD, SIG_IGN); // avoid zombie children

    HttpServer srv;

    // GET / — serve HTML
    srv.route("GET", "/", [&](const HttpRequest&) -> HttpResponse {
        std::string html = HTML;
        if (!bundled_url.empty()) {
            std::string attr = " data-bundle-url=\"" + jesc(bundled_url) + "\"";
            auto pos = html.find("<body");
            if (pos != std::string::npos) {
                auto end = html.find('>', pos);
                if (end != std::string::npos) html.insert(end, attr);
            }
        }
        return HttpResponse::html(html);
    });

    // GET /api/status
    srv.route("GET", "/api/status", [](const HttpRequest&) -> HttpResponse {
        return HttpResponse::json(status_json());
    });

    // POST /api/parse  {url}
    srv.route("POST", "/api/parse", [](const HttpRequest& req) -> HttpResponse {
        std::string url = json_str(req.body, "url");
        if (url.empty()) return HttpResponse::bad_request("missing url");
        try {
            auto p = proxy::parse_uri(url);
            if (!p.valid()) return HttpResponse::json("{\"error\":\"Unsupported protocol\"}");
            std::ostringstream j;
            j << "{\"protocol\":\"" << jesc(p.protocol_name()) << "\""
              << ",\"name\":\""     << jesc(p.name)            << "\""
              << ",\"server\":\""   << jesc(p.server)          << "\""
              << ",\"port\":"       << p.port
              << ",\"security\":\""  << jesc(p.security)       << "\""
              << ",\"sni\":\""      << jesc(p.sni)             << "\""
              << ",\"flow\":\"\"}";
            return HttpResponse::json(j.str());
        } catch (std::exception& e) {
            return HttpResponse::json(std::string("{\"error\":\"") + jesc(e.what()) + "\"}");
        }
    });

    // POST /api/connect  {url}
    srv.route("POST", "/api/connect", [](const HttpRequest& req) -> HttpResponse {
        std::string url = json_str(req.body, "url");
        if (url.empty()) return HttpResponse::bad_request("missing url");
        do_disconnect();
        std::thread([url]{
            try { do_connect(url); }
            catch (std::exception& e) {
                std::lock_guard<std::mutex> lk(g_mu);
                g_state = "error";
                g_last_error = e.what();
            }
        }).detach();
        {
            std::lock_guard<std::mutex> lk(g_mu);
            g_state = "connecting";
        }
        return HttpResponse::json(status_json());
    });

    // POST /api/disconnect
    srv.route("POST", "/api/disconnect", [](const HttpRequest&) -> HttpResponse {
        do_disconnect();
        return HttpResponse::json(status_json());
    });

    std::string sb = find_singbox();
    if (sb.empty())
        push_log("WARNING: sing-box not found! Install: brew install sing-box");
    else
        push_log("sing-box found: " + sb);

    if (!bundled_url.empty())
        push_log("Bundled URL: " + bundled_url.substr(0, 40) + "...");

    // Start listening BEFORE opening the browser so the port is ready.
    if (!srv.prepare(GUI_PORT)) {
        std::cerr << "ERROR: Cannot bind port " << GUI_PORT
                  << " (already in use?)" << std::endl;
        return;
    }

    push_log("GUI server listening on http://127.0.0.1:" + std::to_string(GUI_PORT));
    std::cout << "Veil GUI running at http://127.0.0.1:" << GUI_PORT << "\n"
              << "Press Ctrl+C to quit." << std::endl;

    ::system(("open http://127.0.0.1:" + std::to_string(GUI_PORT) + " &").c_str());

    srv.run();  // accept loop, blocks forever
}

