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
- Automatic macOS system SOCKS5 proxy configuration with previous proxy settings restored on disconnect
- Bundled sing-box support, automatic download, or local binary selection from the UI
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
| sing-box | v1.11.4 (pinned; bundled, downloaded automatically, or selected locally) |

---

## Quick start (pre-built)

1. Download the archive for your Mac from the [latest release](../../releases/latest):
   - `veil-macos-arm64.zip` for Apple Silicon
   - `veil-macos-x86_64.zip` for Intel
2. Download the matching `.sha256` file and verify the archive:
   ```bash
   shasum -a 256 -c veil-macos-arm64.zip.sha256
   ```
3. Unzip and drag `veil.app` to `/Applications`.
4. Open the app — if sing-box is missing, download it automatically or choose a local `sing-box` executable.
5. Paste a proxy URL and click **Connect**.

> **Gatekeeper prompt:** if you use an unsigned local build, macOS may show an "unidentified developer" warning. Signed and notarized release builds should open normally.

---

## Build from source

```bash
# Clone
git clone https://github.com/Malatiel/veilVPN.git
cd veilVPN

# Build the macOS app (uses SING_BOX_BINARY when set, otherwise downloads pinned sing-box)
cd App && bash build.sh

# The app is now at ../veil.app
open ../veil.app
```

Official release archives contain the SwiftUI macOS app and bundled sing-box only.
For offline/local builds, point `SING_BOX_BINARY` at an existing executable:

```bash
cd App
SING_BOX_BINARY=/path/to/sing-box bash build.sh
```

### Run tests

```bash
# Swift tests (proxy parser, profile manager, VPN manager)
swift test

# C++ tests (proxy parser, config persistence, WireGuard crypto & protocol)
cmake -B cmake-build-debug
cmake --build cmake-build-debug
ctest --test-dir cmake-build-debug -V
```

Pull requests are expected to keep both Swift and C++ tests green. See
[CONTRIBUTING.md](CONTRIBUTING.md) for local checks and privacy review steps.
For release steps, see [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).

The C++ test suite includes:

- **test_proxy_parser** — VLESS / VMess / Shadowsocks / Trojan parsing, structural VMess JSON decoding, IPv6, URL encoding, edge cases (malformed brackets, invalid ports, empty URIs), config generation, JSON escaping of control characters
- **test_config** — config persistence with file-permission validation
- **test_shared_cases** — cross-validates C++ and Swift parsers against the same JSON test vectors (`Tests/shared_test_cases.json`)
- **test_wireguard** — BLAKE2s hashing, HKDF key derivation, ChaCha20-Poly1305 AEAD (roundtrip, wrong key, tampered ciphertext, wrong counter), Curve25519 keypair generation and DH, base64 encoding/decoding, nonce construction, Noise replay window (sequential, out-of-order, duplicates, boundary, large jumps, non-mutating pre-auth checks), TAI64N timestamps, protocol struct sizes

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
│   ├── ContentView.swift       # Navigation shell and app-level actions
│   ├── StatusScreen.swift      # Main connection screen
│   ├── ProfilesScreen.swift    # Profile list and import UI
│   ├── LogScreen.swift         # Connection diagnostics log
│   ├── SettingsScreen.swift    # App settings
│   ├── SharedViews.swift       # Reusable SwiftUI components
│   ├── VPNManager.swift        # sing-box lifecycle, proxy settings, TCP ping
│   ├── ProxyParser.swift       # URL parser, config generator, URL export
│   ├── ProfileManager.swift    # Multi-profile CRUD, persistence (~/.veil/)
│   ├── StatusSummary.swift     # Presentation model for connection state
│   ├── ProfilesSummary.swift   # Presentation model for profile state
│   ├── SettingsSummary.swift   # Presentation model for settings state
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
│   └── main.cpp                # CLI entry point
│
├── Tests/
│   ├── ProxyParserTests.swift  # Swift XCTests (parser, Codable, toURL round-trip)
│   ├── test_proxy_parser.cpp   # C++ parser tests (edge cases, config gen)
│   ├── test_wireguard.cpp      # C++ crypto/protocol tests
│   ├── test_config.cpp         # Config persistence and file permissions
│   ├── test_shared_cases.cpp   # C++ runner for shared conformance tests
│   └── shared_test_cases.json  # Shared test vectors for both parsers
│
└── .github/workflows/release.yml  # CI: builds app and publishes releases
```

The Swift app (`App/`) is the only user-facing UI shipped in release archives. The C++ code (`src/`) is a development CLI/core test target for WireGuard-oriented workflows and parser validation. The parser logic is implemented independently in each language, and a shared JSON test suite (`Tests/shared_test_cases.json`) helps keep the two implementations in sync.

---

## How it works

1. **Parse** — the proxy URL is validated and decoded into a `ProxyConfig` struct.
2. **Generate** — a sing-box JSON configuration is written to `~/.veil/singbox.json` with owner-only permissions (`0600`).
3. **Launch** — sing-box is started as a child process; its output is tailed into the log view.
4. **Proxy** — current macOS SOCKS5 proxy settings are saved, then the system SOCKS5 proxy is set to `127.0.0.1:10808` for all active network services.
5. **Monitor** — a background timer measures TCP RTT to the VPN server every 3 s and displays it in the status card.
6. **Cleanup** — on disconnect, sing-box is terminated, the saved SOCKS5 proxy settings are restored, and the generated config file is deleted.

---

## Security notes

- **No shell execution in the C++ core**: all external commands (`route`, `ifconfig`, `networksetup`) are invoked via `fork`/`execvp` with argument arrays — no shell is involved, eliminating command-injection surface entirely.
- **sing-box supply chain**: the binary is downloaded from a **pinned release tag** (`v1.11.4`) with **SHA256 checksum verification** in both the build script and the Swift app. To update, change the version, tag, and hashes in `App/build.sh` and `App/VPNManager.swift`.
- **Profile storage**: saved profiles (`~/.veil/profiles.json`) are written with `0600` permissions — only the owner can read credentials. No sensitive data is stored in UserDefaults.
- The generated sing-box config file (`~/.veil/singbox.json`) is written with `0600` permissions so other local users cannot read VPN credentials.
- **Input validation**: URI parsing includes bounds-checked IPv6 bracket stripping, guarded `std::stoi` conversions, and safe `std::string::compare` for scheme detection. IP addresses and interface names are validated before use.
- All user-supplied strings are JSON-escaped before being embedded in the sing-box config (including control characters such as `\n`, `\r`, `\t`).
- In the Swift app, `networksetup` is invoked via `Process` with an argument array — no shell is involved, so network service names with special characters cannot cause command injection.
- Before enabling the local SOCKS5 proxy, the Swift app snapshots each network service's previous SOCKS proxy state and restores it on disconnect instead of blindly disabling user proxy settings.
- **Standalone cryptography**: Curve25519, ChaCha20-Poly1305, and BLAKE2s are implemented from scratch with no external dependencies. The implementations are covered by unit tests including AEAD roundtrip, wrong-key rejection, ciphertext tampering detection, and DH shared-secret agreement.
- Clipboard operations (copy link, copy log) are triggered only by explicit user action.

For vulnerability reporting and supported versions, see [SECURITY.md](SECURITY.md).
For local data handling, logs, clipboard behavior, and uninstall notes, see
[PRIVACY.md](PRIVACY.md).
For common local issues, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
For safe support requests, see [SUPPORT.md](SUPPORT.md).

---

## Project documents

- [CHANGELOG.md](CHANGELOG.md) — release notes.
- [CONTRIBUTING.md](CONTRIBUTING.md) — local checks and pull request rules.
- [SECURITY.md](SECURITY.md) — vulnerability reporting and security boundaries.
- [PRIVACY.md](PRIVACY.md) — local data and log handling.
- [SUPPORT.md](SUPPORT.md) — safe support request guidance.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — common local issues.
- [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) — release process.

---

## License

MIT
