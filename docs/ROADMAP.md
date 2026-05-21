# Roadmap

This roadmap fixes the product direction for the main Veil application.

## Product Direction

Veil is a lightweight macOS client built around a SwiftUI menu bar app and the
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
- Veil generates sing-box configuration, launches sing-box, tails logs, and
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

The existing C++ code is not the production runtime path for the macOS app.
It is retained for now as legacy/experimental R&D and test history.

Future options:

- move native-core experiments to a separate branch or repository;
- migrate useful test vectors or protocol notes into documentation;
- remove unused C++ source and C++ CI from the main app after an explicit
  cleanup decision.

Deleting the C++ tree should be handled as a separate change, not mixed into a
feature or release-preparation commit.

## Near-Term Priorities

### v1.0.x Stability

- Keep release checks green for Swift tests, C++ legacy tests while present,
  privacy scan, app build, checksums, and release artifact verification.
- Keep sing-box pinned and checksum-verified.
- Keep diagnostics redacted by default.
- Keep crash and force-quit recovery focused on restoring system proxy state.

### v1.1 User Experience

- Add screenshots and a short demo flow to the README.
- Add issue templates with warnings not to paste proxy URLs, UUIDs, passwords,
  or raw logs.
- Add a Settings action to reset macOS SOCKS proxy settings.
- Improve connection errors with clearer next actions.
- Improve first-run guidance for selecting or downloading sing-box.

### v1.2 Profile Management

- Add subscription import and refresh.
- Add profile groups or folders.
- Add QR import.
- Add latency refresh for multiple profiles and optional sorting.
- Add safer profile export with an explicit confirmation when credentials are
  included.

### v1.3 Distribution and Trust

- Configure Developer ID signing and notarization when Apple credentials are
  available.
- Add a release verification section with screenshots in the GitHub release
  body.
- Add automated UI smoke coverage or an internal smoke mode that does not
  require screen recording or accessibility permissions.
- Keep a clear changelog for every release.

## Native Engine Fork Option

If Veil later needs a native protocol engine without sing-box, that work should
start as a fork, separate branch, or separate repository with its own threat
model, tests, benchmarks, and release criteria.

The main app should remain sing-box-backed until a native implementation has
earned comparable trust.
