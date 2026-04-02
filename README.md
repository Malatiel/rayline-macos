# Veil

A lightweight macOS VPN client for **VLESS**, **VMess**, **Shadowsocks**, and **Trojan** protocols.
Connects via [sing-box](https://github.com/SagerNet/sing-box) and sets the system SOCKS5 proxy automatically.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-supported-green)
![Intel](https://img.shields.io/badge/Intel-supported-green)

---

## Features

- Paste a proxy URL and connect in one click
- Supports **VLESS** (TCP / WS / gRPC / HTTP/2, TLS, REALITY), **VMess**, **Shadowsocks** (SIP002 + legacy), **Trojan**
- Live **TCP latency** display (RTT to the VPN server, updated every 3 s)
- Packet sent / received counters
- Automatic macOS system SOCKS5 proxy configuration and cleanup on disconnect
- Bundled sing-box — no manual installation needed (downloaded automatically on first launch)
- **Supply-chain protection**: sing-box is downloaded from a pinned release with SHA256 checksum verification
- IPv4 and **IPv6** endpoint support in the WireGuard transport
- Structured log view with ANSI colour stripping

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 13 Ventura or newer |
| Architecture | Apple Silicon (arm64) or Intel (x86_64) |
| Xcode Command Line Tools | any recent version (`xcode-select --install`) |
| sing-box | v1.11.4 (pinned; downloaded automatically by the app) |

---

## Quick start (pre-built)

1. Download `veil-macos.zip` from the [latest release](../../releases/latest).
2. Unzip and drag `veil.app` to `/Applications`.
3. Open the app — on first launch sing-box (~15 MB) is downloaded automatically.
4. Paste a proxy URL and click **Connect**.

> **Gatekeeper prompt:** right-click the app → Open → Open to bypass the "unidentified developer" warning.

---

## Build from source

```bash
# Clone
git clone https://github.com/your-username/Veil.git
cd veil

# Build the macOS app (downloads sing-box, compiles Swift)
cd App && bash build.sh

# The app is now at ../veil.app
open ../veil.app
```

### Run tests

```bash
# Swift tests (proxy parser)
swift test

# C++ tests (proxy parser + config generation + shared conformance)
cmake -B cmake-build-debug
cmake --build cmake-build-debug
ctest --test-dir cmake-build-debug -V
```

The shared test suite (`Tests/shared_test_cases.json`) validates both the C++ and Swift proxy parsers against the same set of URIs and expected values, preventing behavioural drift between the two implementations.

---

## Supported URL formats

| Protocol | Example |
|---|---|
| VLESS | `vless://uuid@host:port?security=reality&pbk=...&sid=...&fp=chrome#Name` |
| VMess | `vmess://base64encodedJSON` |
| Shadowsocks | `ss://base64(method:password)@host:port#Name` |
| Trojan | `trojan://password@host:port?security=tls&sni=host#Name` |

URLs can be pasted directly from share links — embedded whitespace and line-breaks (introduced by some messengers) are stripped automatically before parsing.

---

## Architecture

```
Veil/
├── App/                    # Swift macOS app (SwiftUI)
│   ├── VeilApp.swift       # App entry point
│   ├── ContentView.swift   # UI
│   ├── VPNManager.swift    # sing-box lifecycle, proxy settings, TCP ping
│   ├── ProxyParser.swift   # URL parser + sing-box config generator
│   └── build.sh            # Build script (downloads sing-box, compiles Swift)
│
├── src/                    # C++ core (WireGuard client, CLI)
│   ├── proxy/              # Proxy URL parser (C++ implementation)
│   ├── wireguard/          # WireGuard handshake & packet processing
│   ├── crypto/             # Curve25519, ChaCha20-Poly1305, BLAKE2s
│   ├── tun/                # TUN interface management
│   ├── network/            # Route and DNS management
│   ├── frontend/           # Embedded HTTP GUI server (alternative UI)
│   └── main.cpp            # CLI entry point
│
├── Tests/
│   ├── ProxyParserTests.swift    # 44 Swift XCTests
│   ├── test_proxy_parser.cpp     # 23 C++ unit tests
│   ├── test_shared_cases.cpp     # C++ runner for shared conformance tests
│   └── shared_test_cases.json    # Shared test vectors for both parsers
│
└── .github/workflows/release.yml  # CI: builds app and publishes releases
```

The Swift app (`App/`) is the primary user-facing component. The C++ code (`src/`) provides a standalone CLI and an alternative embedded HTTP GUI; both share the same proxy-URL parsing logic implemented independently in each language. A shared JSON test suite (`Tests/shared_test_cases.json`) ensures both implementations stay in sync.

---

## How it works

1. **Parse** — the proxy URL is validated and decoded into a `ProxyConfig` struct.
2. **Generate** — a sing-box JSON configuration is written to `/tmp/veil_singbox.json` with owner-only permissions (`0600`).
3. **Launch** — sing-box is started as a child process; its output is tailed into the log view.
4. **Proxy** — macOS system SOCKS5 proxy is set to `127.0.0.1:10808` for all active network services.
5. **Monitor** — a background timer measures TCP RTT to the VPN server every 3 s and displays it in the status card.
6. **Cleanup** — on disconnect, sing-box is terminated, the SOCKS5 proxy is cleared, and the temporary config file is deleted.

---

## Security notes

- **sing-box supply chain**: the binary is downloaded from a **pinned release tag** (`v1.11.4`) with **SHA256 checksum verification** in both the build script and the Swift app. To update, change the version, tag, and hashes in `App/build.sh` and `App/VPNManager.swift`.
- The temporary config file (`/tmp/veil_singbox.json`) is written with `0600` permissions so other local users cannot read VPN credentials.
- The embedded HTTP GUI server (`127.0.0.1:18080`) does **not** send `Access-Control-Allow-Origin: *`, preventing cross-origin requests from arbitrary websites.
- All user-supplied strings are JSON-escaped before being embedded in the sing-box config (including control characters such as `\n`, `\r`, `\t`).
- `networksetup` is invoked via `Process` with an argument array — no shell is involved, so network service names with special characters cannot cause command injection.
- **DNS restoration**: when the VPN disconnects, both `networksetup` DNS settings and `/etc/resolv.conf` are restored to their pre-connection state. The active network service is determined by the interface associated with the default route, not by list order.

---

## License

MIT
