# Changelog

All notable user-facing changes should be documented in this file.

This project uses semantic versioning where possible:

- patch releases for bug fixes, documentation, CI, and packaging improvements;
- minor releases for backward-compatible features;
- major releases for breaking changes.

## Unreleased

### Added

- GitHub issue templates now warn users not to paste proxy links, UUIDs,
  passwords, local paths, or raw logs.
- Support docs now describe safe redacted diagnostics export.
- Settings now includes a manual action to reset macOS SOCKS proxy state after
  interrupted sessions.

## 1.0.9 - 2026-05-21

### Changed

- Documented the product direction as a SwiftUI macOS app backed by sing-box,
  with native protocol experiments kept outside the production runtime path.
- Archived the legacy C++ native-core experiment on `archive-native-cpp-core`
  and removed the unused C++ build and test path from `main`.

## 1.0.8 - 2026-05-21

### Added

- Local release artifact verifier for ZIP archives, SHA256 files, app metadata,
  and bundled executables.
- Startup recovery for saved SOCKS proxy settings after interrupted sessions.
- Stale Veil-owned sing-box process detection on app launch.
- Redacted diagnostics export from the log screen.

### Changed

- Connection error states now show targeted recovery hints.
- Release checklist and privacy docs now cover artifact verification,
  diagnostics export, and proxy recovery state.
- GitHub Actions workflows now opt into Node.js 24 and use Node 24-compatible
  checkout, artifact, and release actions.

## 1.0.7 - 2026-05-20

### Added

- Release workflow SHA256 checksum files for published macOS ZIP archives.
- BDD-style summary tests for Status, Profiles, and Settings screen behavior.

### Changed

- Split the SwiftUI app shell into focused Status, Profiles, Log, Settings, and
  shared view files.
- Reduced `ContentView` to navigation, orchestration, and app-level actions.
- Bumped macOS app version to `1.0.7`.

## 1.0.6 - 2026-05-20

### Added

- Public CI workflow for Swift and C++ tests on pull requests and pushes to
  `main`.
- Security policy with vulnerability reporting guidance and security boundaries.
- Privacy policy describing local data, logs, clipboard behavior, and network
  access.
- Contributor guide and pull request checklist with privacy/security review
  steps.

### Changed

- Bumped macOS app version to `1.0.6`.

## 1.0.5 - 2026-05-04

### Changed

- Prepared release `v1.0.5`.

### Notes

- See Git history for detailed changes before this changelog was introduced.
