# Troubleshooting

This page lists common local issues and safe diagnostics.

## The App Does Not Open

- Confirm macOS 13 or newer.
- If this is an unsigned local build, macOS Gatekeeper may require explicit
  approval in System Settings.
- If the app was built locally, rebuild from a clean checkout.

## sing-box Is Missing

Veil can use sing-box in three ways:

- bundled inside the release archive;
- downloaded automatically by the app;
- selected manually from a local executable.

For offline builds, pass a local executable to the build script:

```bash
cd App
SING_BOX_BINARY=/path/to/sing-box bash build.sh
```

Do not commit local sing-box binaries to the repository.

## Connection Fails

1. Check that the proxy link is complete and uses a supported scheme:
   `vless://`, `vmess://`, `ss://`, or `trojan://`.
2. Use the built-in Check action before saving a profile.
3. Review the Log tab and redact credentials before sharing any lines.
4. Confirm that another process is not already using `127.0.0.1:10808`.

## System Proxy Was Not Restored

Veil snapshots SOCKS proxy settings before connecting and restores them on
disconnect. If the app or sing-box exits unexpectedly:

1. Reopen Veil and disconnect if it still shows an active state.
2. Open Settings in Veil and use **Reset** next to System proxy.
3. Check macOS network proxy settings manually.
4. If Proxy Guard was enabled, the SOCKS proxy may intentionally remain active
   until you reconnect or disconnect.

## Logs Contain Sensitive Data

Logs can include server names, ports, and sing-box messages. Before filing an
issue:

- remove real server names if they identify your provider or account;
- remove passwords, UUIDs, private keys, and public/private REALITY material;
- keep only the minimal lines needed to reproduce the issue.
