# Security Policy

Veil is a local macOS proxy/VPN client. It handles proxy credentials, generated
sing-box configuration files, system proxy settings, and network traffic routing.
Please treat security reports as sensitive.

## Supported Versions

Security fixes are provided for the latest public release and the current
`main` branch. Older releases may not receive backported fixes.

## Reporting a Vulnerability

Please do not open a public issue for vulnerabilities.

Use GitHub private vulnerability reporting if it is available for this
repository. If it is not available, contact the maintainer through GitHub and
share only the minimum information needed to establish a private channel.

Useful report details:

- affected Veil version or commit;
- macOS version and CPU architecture;
- whether sing-box was bundled, downloaded by Veil, or selected manually;
- reproduction steps with test credentials only;
- expected and actual impact.

Do not include real proxy links, passwords, private keys, Apple certificates,
personal network names, or logs containing credentials.

## Security Boundaries

Veil aims to:

- store local profiles and generated sing-box config files with owner-only
  permissions;
- avoid shell execution for user-controlled command arguments;
- verify downloaded sing-box archives against pinned SHA256 checksums;
- restore previous macOS SOCKS proxy settings when disconnecting.

Veil does not claim to provide anonymity guarantees, censorship-resistance
guarantees, malware protection, or audited cryptographic implementations.

## Dependency Updates

The bundled/downloaded sing-box version is pinned in both `App/build.sh` and
`App/VPNManager.swift`. Updating sing-box requires updating the version, release
tag, SHA256 checksums, and compatibility tests for generated configuration.
