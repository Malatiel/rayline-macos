# Veil

A lightweight macOS VPN client for **VLESS**, **VMess**, **Shadowsocks**, and **Trojan** protocols.
Connects via [sing-box](https://github.com/SagerNet/sing-box) and sets the system SOCKS5 proxy automatically.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-supported-green)
![Intel](https://img.shields.io/badge/Intel-supported-green)

---

## Features

- **Multiple profiles** — save, rename, delete, and switch between proxy profiles (stored locally in `~/.veil/profiles.json` with `0600` permissions); WireGuard configs live in `~/.veil/wireguard/`
- **Export / copy link** — reconstruct a shareable proxy URL from any saved profile
- **Auto-connect** — optionally reconnect to the active profile on app launch
- Supports **VLESS** (TCP / WS / gRPC / HTTP/2, TLS, REALITY), **VMess**, **Shadowsocks** (SIP002 + legacy), **Trojan**
- Live **TCP latency** display (RTT to the VPN server, updated every 3 s) with manual refresh
- Packet sent / received counters
- **Theme switcher** — system, light, or dark appearance
- **Toast notifications** — on connect, disconnect, error, and clipboard actions
- **Log filtering** — search by text, filter by level (all / error / warning / info), copy to clipboard
- Automatic macOS system SOCKS5 proxy configuration and cleanup on disconnect
- Bundled sing-box — no manual installation needed (downloaded automatically on first launch)
- **Supply-chain protection**: sing-box is downloaded from a pinned release with SHA256 checksum verification
- IPv4 and **IPv6** endpoint support
- Bilingual UI (Russian / English)

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
├── App/                        # Swift macOS app (SwiftUI)
│   ├── VeilApp.swift           # App entry point (MenuBarExtra)
│   ├── ContentView.swift       # UI (status, profiles, log, settings)
│   ├── VPNManager.swift        # sing-box lifecycle, proxy settings, TCP ping
│   ├── ProxyParser.swift       # URL parser, config generator, URL export
│   ├── ProfileManager.swift    # Multi-profile CRUD, persistence (~/.veil/)
│   ├── LanguageManager.swift   # Bilingual support (RU / EN)
│   ├── ThemeManager.swift      # System / light / dark appearance
│   ├── ToastManager.swift      # Toast notification state
│   └── build.sh                # Build script (downloads sing-box, compiles Swift)
│
├── src/                        # C++ core (WireGuard client, CLI)
│   ├── proxy/                  # Proxy URL parser (C++ implementation)
│   ├── wireguard/              # WireGuard handshake & packet processing
│   ├── crypto/                 # Curve25519, ChaCha20-Poly1305, BLAKE2s
│   ├── tun/                    # TUN interface management
│   ├── network/                # Route and DNS management
│   ├── frontend/               # Embedded HTTP GUI server (alternative UI)
│   └── main.cpp                # CLI entry point
│
├── Tests/
│   ├── ProxyParserTests.swift  # 58 Swift XCTests (parser, Codable, toURL round-trip)
│   ├── test_proxy_parser.cpp   # C++ unit tests
│   ├── test_shared_cases.cpp   # C++ runner for shared conformance tests
│   └── shared_test_cases.json  # Shared test vectors for both parsers
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
- **Profile storage**: saved profiles (`~/.veil/profiles.json`) are written with `0600` permissions — only the owner can read credentials. No sensitive data is stored in UserDefaults.
- The temporary config file (`/tmp/veil_singbox.json`) is written with `0600` permissions so other local users cannot read VPN credentials.
- The embedded HTTP GUI server (`127.0.0.1:18080`) does **not** send `Access-Control-Allow-Origin: *`, preventing cross-origin requests from arbitrary websites.
- All user-supplied strings are JSON-escaped before being embedded in the sing-box config (including control characters such as `\n`, `\r`, `\t`).
- `networksetup` is invoked via `Process` with an argument array — no shell is involved, so network service names with special characters cannot cause command injection.
- Clipboard operations (copy link, copy log) are triggered only by explicit user action.

---

## License

MIT
