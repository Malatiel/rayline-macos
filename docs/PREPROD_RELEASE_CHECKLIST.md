# Preprod Release Checklist

Use this checklist for a release candidate such as `v1.1.0-rc.1`. A preprod
release is intended for testing and feedback, not as the final stable release.

## Version

- Set `CFBundleShortVersionString` in `App/Info.plist` to the target product
  version, for example `1.1.0`.
- Increment `CFBundleVersion`.
- Move user-facing changes from `Unreleased` to the release-candidate entry in
  `CHANGELOG.md`.
- Confirm the intended tag name, for example `v1.1.0-rc.1`.
- Confirm the tag does not already exist:

```bash
git tag --list 'v1.1.0*'
```

## Local Automated Verification

Run:

```bash
swift test
bash scripts/privacy_scan.sh
git diff --check
```

Build the app:

```bash
cd App
CI=1 bash build.sh
```

If building offline, use a local sing-box executable:

```bash
cd App
CI=1 SING_BOX_BINARY=/path/to/sing-box bash build.sh
```

## Local Artifact Verification

Create a local archive and checksum:

```bash
mkdir -p release
ditto -c -k --keepParent /path/to/Veil.app release/veil-macos-arm64.zip
cd release
shasum -a 256 veil-macos-arm64.zip > veil-macos-arm64.zip.sha256
shasum -a 256 -c veil-macos-arm64.zip.sha256
EXPECTED_VERSION=1.1.0 EXPECTED_BUILD=10 ../scripts/verify_release_artifact.sh veil-macos-arm64.zip
```

Do not commit local `release/` artifacts.

## Manual GUI Verification

- Complete [MANUAL_GUI_CHECKLIST.md](MANUAL_GUI_CHECKLIST.md).
- Record which archive, architecture, macOS version, and app build were tested.
- Do not publish screenshots or logs containing personal data or real proxy
  credentials.

## GitHub Actions Verification

After pushing the release-candidate tag:

- Confirm Privacy scan succeeds.
- Confirm Swift tests succeed.
- Confirm arm64 build succeeds.
- Confirm x86_64 build succeeds.
- Confirm release publishing succeeds.
- Confirm no Node.js runtime deprecation warnings appear.
- Download all release assets:
  - `veil-macos-arm64.zip`
  - `veil-macos-arm64.zip.sha256`
  - `veil-macos-x86_64.zip`
  - `veil-macos-x86_64.zip.sha256`
- Verify both checksums locally.
- Run `scripts/verify_release_artifact.sh` for both archives.

## Release Candidate Notes

The GitHub pre-release body should clearly say:

- this is a release candidate;
- GUI testing is manual;
- the app is a SwiftUI macOS client backed by sing-box;
- subscription URLs may contain secrets and should not be shared publicly;
- notarization status depends on whether Apple Developer ID credentials are
  configured for the release workflow.

## Stop Conditions

Do not publish a stable release if any of these are true:

- tests, privacy scan, app build, checksum verification, or artifact
  verification fails;
- manual GUI checklist finds a blocking issue;
- release assets are missing `.zip` or `.sha256` files;
- a real proxy link, token, password, email, local path, or raw private log is
  staged, committed, attached, or published.
