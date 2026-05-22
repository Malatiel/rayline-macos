# Known Limitations

This document describes current limitations honestly so users can decide
whether Veil fits their needs.

## Release Status

- `v1.1.0-rc.1` is intended as a pre-release candidate.
- Expect rough edges and report issues with redacted diagnostics only.
- Stable release readiness depends on successful CI, artifact verification, and
  manual GUI verification.

## macOS Signing And Notarization

- Local builds are ad-hoc signed.
- GitHub release builds can use Developer ID signing and notarization only when
  Apple credentials are configured as repository secrets.
- Without notarization, macOS Gatekeeper may show an unidentified developer
  warning.

## GUI Testing

- GUI clickability is currently checked manually.
- Automated core tests cover parsing, profiles, subscriptions, diagnostics,
  lifecycle recovery, settings summaries, and release artifact checks.
- Menu bar UI automation may require Accessibility or Screen Recording
  permissions, which are intentionally not required for normal development.

## Network And Latency

- Profile latency is a TCP reachability and RTT signal to the configured server,
  not a throughput benchmark.
- A low latency value does not guarantee the best real-world VPN speed.
- Timeout means the TCP check did not complete during the measurement window;
  it does not prove the server is permanently offline.

## Protocol Backend

- Veil uses sing-box as the production protocol backend.
- The app does not ship a self-written production protocol engine.
- Native protocol experiments, if any, should remain outside the production
  runtime path until they have their own threat model, tests, benchmarks, and
  review.

## Subscriptions

- Subscription URLs may contain account tokens and should be treated as
  secrets.
- Refresh is manual.
- Empty or fully invalid subscription refreshes fail safely without deleting
  existing profiles from that subscription.
- Veil keeps the provider order from the subscription rather than sorting
  profiles by latency.

## Privacy

- Veil has no analytics, telemetry, advertising SDKs, crash reporting service,
  or remote account system.
- Logs and diagnostics can still contain server names or operational details.
  Review exported diagnostics before sharing them.
