# Privacy

Veil is designed as a local macOS application. It does not include analytics,
telemetry, crash reporting, advertising SDKs, or a remote account system.

## Data Stored Locally

Veil may store the following data on your Mac:

- proxy profiles in `~/.veil/profiles.json`;
- subscription sources in `~/.veil/subscriptions.json`;
- generated sing-box configuration in `~/.veil/singbox.json` while connected;
- sing-box logs in `~/.veil/singbox.log`;
- previous SOCKS proxy settings in `~/.veil/proxy-state.json` while Veil is
  connected or recovering after an interrupted session;
- downloaded sing-box binary in `~/.veil/sing-box`;
- app preferences in macOS UserDefaults, such as theme, language, auto-connect,
  selected profile id, and custom sing-box path.

Profiles, subscription URLs, and generated config files may contain proxy
credentials or account tokens. These files are intended to be written with
owner-only permissions.

## Network Access

Veil connects to:

- the proxy server configured by the user;
- HTTP(S) subscription URLs saved by the user when manually refreshing them;
- GitHub releases when downloading the pinned sing-box archive;
- local macOS system tools used to read and update SOCKS proxy settings.

Veil does not intentionally send proxy profiles, credentials, logs, or app
preferences to the project maintainer.

## Logs

Logs may include server names, ports, sing-box messages, and operational errors.
Do not share logs publicly without reviewing and redacting sensitive details.

## Diagnostics Export

The app can export a local diagnostics text file from the log screen. The export
redacts proxy URLs, UUIDs, common secret query parameters, email addresses, and
local filesystem paths before writing the file with owner-only permissions.

## Clipboard

Veil can copy proxy links or logs only after an explicit user action. Copied
content may contain credentials.

## Uninstalling Local Data

Quit Veil, disconnect first if needed, then remove local app data:

```bash
rm -rf ~/.veil
```

You may also remove Veil-related preferences from macOS UserDefaults if desired.
