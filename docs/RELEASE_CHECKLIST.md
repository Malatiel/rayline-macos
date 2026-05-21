# Release Checklist

Use this checklist before pushing a release tag.

## Version

- Update `CFBundleShortVersionString` and `CFBundleVersion` in
  `App/Info.plist`.
- Add a new entry to `CHANGELOG.md`.
- Confirm GitHub Release artifacts will include `veil-macos-<arch>.zip` and
  `veil-macos-<arch>.zip.sha256`.
- Confirm the tag does not already exist:

```bash
git tag --list 'v*'
```

## Local Verification

Run Swift tests:

```bash
swift test
```

Run C++ tests:

```bash
cmake -B cmake-build-debug -DCMAKE_BUILD_TYPE=Release
cmake --build cmake-build-debug
ctest --test-dir cmake-build-debug -V
```

Build the macOS app:

```bash
cd App
CI=1 bash build.sh
```

If building offline, use a local executable:

```bash
cd App
CI=1 SING_BOX_BINARY=/path/to/sing-box bash build.sh
```

Create and verify local release artifacts:

```bash
mkdir -p release
ditto -c -k --keepParent /path/to/Veil.app release/veil-macos-arm64.zip
cd release
shasum -a 256 veil-macos-arm64.zip > veil-macos-arm64.zip.sha256
shasum -a 256 -c veil-macos-arm64.zip.sha256
EXPECTED_VERSION=X.Y.Z EXPECTED_BUILD=N ../scripts/verify_release_artifact.sh veil-macos-arm64.zip
```

## Privacy and Security

- Run `git diff --check`.
- Run `bash scripts/privacy_scan.sh`.
- Review `git status --short`.
- Review staged changes for personal data, credentials, private keys, logs, and
  machine-specific paths.
- Do not commit real proxy links or local sing-box binaries.
- Confirm generated artifacts remain ignored by `.gitignore`.
- Confirm local `release/` artifacts are not staged.

## Publish

Create and push the release commit, then tag it:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

The tag push starts the GitHub release workflow.

## After Publishing

- Confirm GitHub Actions completed for Swift tests, C++ tests, and both app
  architectures.
- Download the release archives and `.sha256` files.
- Verify each archive with `shasum -a 256 -c veil-macos-<arch>.zip.sha256`.
- Run `scripts/verify_release_artifact.sh` against each downloaded archive.
- Confirm the verified archives unzip cleanly.
- Launch the app on a test Mac.
- Open the menu bar window and check import, save profile, settings, logs, and
  quit actions.
