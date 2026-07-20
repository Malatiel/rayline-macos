# Known Limitations

This document describes current limitations honestly so users can decide
whether Rayline fits their needs.

## Release Status

- `v1.1.0-rc.1` is intended as a pre-release candidate.
- Expect rough edges and report issues with redacted diagnostics only.
- Stable release readiness depends on successful CI, artifact verification, and
  manual GUI verification.

## Traffic Coverage

This is the most important limitation to understand before relying on Rayline.

- Rayline is not a system-wide VPN and does not create a TUN interface. It runs
  sing-box locally and points the macOS **system SOCKS5 proxy** setting at it.
- Only applications that honour the macOS system proxy setting are routed
  through the proxy. Applications that ignore that setting connect directly,
  in the clear, with your real IP address.
- Applications that commonly ignore the system SOCKS proxy setting include many
  command-line tools, container runtimes, and some applications that ship their
  own network stack.
- UDP traffic is generally not covered by the macOS SOCKS proxy setting, so
  protocols that rely on UDP are typically not routed.
- Traffic to private and loopback addresses is routed directly instead of
  through the proxy, so devices on your own network stay reachable while
  connected. This matches on the destination IP address, so local *hostnames*
  are only covered if the requesting application resolves them to a private
  address before connecting.
- The kill switch keeps the system proxy active when the connection drops, so
  applications that honour the proxy fail closed rather than leaking. It does
  **not** stop traffic from applications that bypass the proxy setting in the
  first place, because that traffic never went through the proxy.
- If your threat model requires that *all* traffic from the machine is covered,
  Rayline in its current form does not meet it.

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
- A low latency value does not guarantee the best real-world proxy speed.
- Timeout means the TCP check did not complete during the measurement window;
  it does not prove the server is permanently offline.

## Protocol Backend

- Rayline uses sing-box as the production protocol backend.
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
- Rayline keeps the provider order from the subscription rather than sorting
  profiles by latency.

## Privacy

- Rayline has no analytics, telemetry, advertising SDKs, crash reporting service,
  or remote account system.
- Logs and diagnostics can still contain server names or operational details.
  Review exported diagnostics before sharing them.
