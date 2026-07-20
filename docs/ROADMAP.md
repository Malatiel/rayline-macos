# Roadmap

This roadmap fixes the product direction for the main Rayline application.

## Product Direction

Rayline is a lightweight macOS client built around a SwiftUI menu bar app and the
sing-box runtime.

The main product goal is not to replace sing-box with a self-written protocol
engine. The goal is to provide a small, trustworthy, native-feeling macOS client
with good profile management, safe diagnostics, reliable proxy cleanup, and a
clear release process.

## Current Production Architecture

- SwiftUI owns the macOS user interface, settings, profiles, diagnostics, and
  system integration.
- sing-box is the production protocol backend for VLESS, VMess, Shadowsocks,
  and Trojan.
- Rayline generates sing-box configuration, launches sing-box, tails logs, and
  manages macOS SOCKS proxy settings.
- Release builds ship the app bundle and the pinned sing-box binary.

## Non-Goals for the Main App

- Do not ship an experimental self-written protocol engine as a user-selectable
  production backend.
- Do not claim performance advantages over sing-box without repeatable
  benchmarks.
- Do not expand the attack surface with native protocol implementations unless
  they are developed, tested, and reviewed as a separate effort.

## C++ Code Status

The legacy C++ native-core experiment is not the production runtime path for
the macOS app and has been removed from `main`.

History remains available on the `archive-native-cpp-core` branch. Future
native-engine work should happen in a fork, separate repository, or explicitly
scoped branch with its own threat model, tests, benchmarks, and release
criteria.

Do not reintroduce a self-written protocol engine into `main` as a selectable
backend without that review work.

## Standing Commitments

These hold for every release rather than belonging to a version.

- Keep release checks green for Swift tests, privacy scan, app build,
  checksums, and release artifact verification.
- Keep sing-box pinned and its download checksum-verified.
- Keep diagnostics redacted by default.
- Keep crash and force-quit recovery focused on restoring system proxy state.
- Keep a clear changelog for every release.

## Shipped in 1.2.0

Recorded here because this work was not on the previous roadmap, which planned
a different 1.2 and left the version describing something the release did not
contain.

- Private and loopback destinations route directly, so the local network stays
  reachable while connected.
- Launch at login.
- Automatic reconnect after an established connection drops, with bounded
  retries and an off switch.
- A tunnel check that proves traffic passes, rather than inferring health from
  a latency reading.
- Scheduled subscription refresh.
- Optional failover across the servers of one subscription, off by default.
- Documentation of what traffic Rayline covers and every outgoing request it
  can make.

## Verification Debt

Carried by the 1.2.0 release and worth closing before adding features. This is
the honest state, not a formality.

- The `x86_64` release artifact has never been verified; only `arm64` was built
  and checked locally.
- `MANUAL_GUI_CHECKLIST.md` has not been run end to end against 1.2.0.
- Launch at login has not been confirmed from an app installed in
  `/Applications`, which is the only place registration can succeed.
- Failover has not been exercised against a subscription with several live
  servers.

## Open Work

### Distribution and Trust

- Developer ID signing and notarization are **already implemented** in
  `.github/workflows/release.yml` and skip themselves when the repository
  secrets are absent. This is blocked on having an Apple Developer account, not
  on code. Until then every user meets a Gatekeeper warning, which is the
  largest single obstacle to anyone actually installing the app.
- Add automated UI smoke coverage, or an internal smoke mode that needs no
  screen recording or accessibility permissions.
- Add screenshots and a short demo flow to the README.

### Correctness and Safety

- `findSingBox()` will run a binary from `/opt/homebrew/bin`, `/usr/local/bin`
  or `/usr/bin` **without verifying it**. Checksum pinning only guards the
  download path, and `/usr/local/bin` is writable without `sudo` on macOS. The
  supply-chain story is weaker than it reads.
- The macOS proxy bypass list (`networksetup -setproxybypassdomains`) is never
  set. Whether local traffic even reaches sing-box may depend on it, so the
  direct route rule might not be the only layer involved in local-network
  access.

### Features

- Domain-based split tunnelling, so chosen domains bypass the proxy. Needs
  sing-box rule-sets in `.srs` format; Xray `geosite.dat` files do not apply.
  This is the most requested capability for this class of client.
- Custom profile groups or folders, distinct from the failover group, which is
  derived from a subscription rather than chosen.
- Improve subscription conflict handling for duplicate remote entries beyond
  the current skip-and-count behaviour.

## Native Engine Fork Option

If Rayline later needs a native protocol engine without sing-box, that work should
start as a fork, separate branch, or separate repository with its own threat
model, tests, benchmarks, and release criteria.

The main app should remain sing-box-backed until a native implementation has
earned comparable trust.
