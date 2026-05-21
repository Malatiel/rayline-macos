# Support

Veil is maintained as an open-source project. Please keep support requests safe
to share publicly.

## Before Opening an Issue

1. Check the latest release notes and open issues.
2. Confirm that you are using macOS 13 or newer.
3. Confirm whether sing-box is bundled, downloaded by Veil, or selected from a
   local path.
4. Try to reproduce with a test profile or synthetic proxy link.
5. Export redacted diagnostics from Veil if logs are needed.

## Export Diagnostics Safely

1. Open Veil.
2. Go to **Log**.
3. Click **Export**.
4. Save `veil-diagnostics.txt`.
5. Open the file and review it before attaching it to an issue.

The diagnostics export redacts proxy URLs, UUIDs, passwords, emails, and local
paths. Still review the file manually: only you know whether a server name,
profile name, or network service name identifies you.

## What to Include

- Veil version;
- macOS version and CPU architecture;
- proxy protocol type, without real credentials;
- whether the issue happens before connect, during connect, or on disconnect;
- redacted diagnostics or short log excerpts;
- whether you use bundled sing-box, downloaded sing-box, or a selected local
  executable.

Synthetic examples are welcome. For example, use `example.com`, `example.org`,
or clearly fake IDs instead of real servers and credentials.

## Do Not Share

- real proxy URLs;
- UUIDs, passwords, private keys, or REALITY private material;
- Apple signing credentials or certificates;
- personal network service names if they identify you;
- local filesystem paths that include your name or organization;
- raw logs or screenshots without reviewing them first.

## Security Reports

Do not open public issues for vulnerabilities. Use the process in
[SECURITY.md](SECURITY.md).
