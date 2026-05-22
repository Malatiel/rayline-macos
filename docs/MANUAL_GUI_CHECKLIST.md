# Manual GUI Checklist

Use this checklist before a pre-release or release when GUI automation is not
available. Run it from a clean temporary profile set when possible.

## Setup

- Build or download the app version under test.
- Quit any running Veil instance.
- Keep real proxy links, subscription URLs, UUIDs, passwords, and raw logs out
  of screenshots and issue comments.
- Prefer synthetic profiles or a test subscription. If you must use a real
  subscription, do not publish screenshots that reveal server names or account
  tokens.

## First Run

- Launch Veil.
- Confirm the menu bar window opens.
- Confirm the first-run checklist is visible when sing-box or profiles are
  missing.
- Open Settings and confirm sing-box status is understandable.
- Confirm language and theme controls are clickable.

## Import And Profiles

- Open Profiles.
- Import a single synthetic profile link.
- Import multiple synthetic profile links in one paste.
- Import or refresh a subscription source.
- Confirm profiles are grouped by subscription source.
- Confirm profile order follows the subscription provider order.
- Confirm profile rows show protocol, route, source label, and latency state:
  `not checked`, `timeout`, or `<N> ms`.
- Rename a profile and confirm the row updates.
- Copy a profile link and confirm the toast appears.

## Subscription Refresh

- Refresh one subscription.
- Refresh all subscriptions.
- Confirm new profiles are added.
- Confirm renamed remote profiles update without changing the connection.
- Confirm removed remote profiles disappear from that subscription.
- Confirm a manual profile that is not part of the subscription remains.
- Confirm an empty or fully invalid subscription refresh shows an error and
  does not delete existing profiles.
- Confirm the subscription row shows profile count, last refresh status, and
  the latest summary or error.

## Fastest And Latency

- Click Fastest for a subscription.
- Confirm the active profile changes only when a reachable fastest profile is
  found.
- Confirm latency states are written to profile rows.
- Confirm profile order does not change after latency checks.
- Confirm timeout profiles remain visible and are not selected as fastest when
  another profile has a measured latency.

## Connect And Disconnect

- Select a profile.
- Connect.
- Confirm status changes to connected and traffic counters are visible.
- Confirm logs update without exposing credentials in UI text.
- Disconnect.
- Confirm status returns to disconnected.
- Confirm macOS SOCKS proxy state is restored.

## Diagnostics

- Open Log.
- Export diagnostics.
- Open the exported file and manually review it.
- Confirm proxy URLs, UUIDs, passwords, emails, and local filesystem paths are
  redacted.
- Confirm the file is safe before attaching it to an issue.

## Recovery

- Open Settings.
- Confirm Reset SOCKS Proxy is disabled while connected.
- Disconnect.
- Run Reset SOCKS Proxy.
- Confirm the action completes and shows a clear result.

## Release Notes Evidence

- Record the app version and build number.
- Record the macOS version and architecture used for the manual check.
- Record which release archive was tested.
- Do not attach screenshots containing real server names, proxy links, account
  tokens, emails, local paths, or personal network service names.
