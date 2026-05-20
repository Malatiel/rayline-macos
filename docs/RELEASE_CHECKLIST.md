# Release Checklist

Use this checklist before pushing a release tag.

## Version

- Update `CFBundleShortVersionString` and `CFBundleVersion` in
  `App/Info.plist`.
- Add a new entry to `CHANGELOG.md`.
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

## Privacy and Security

- Run `git diff --check`.
- Review `git status --short`.
- Review staged changes for personal data, credentials, private keys, logs, and
  machine-specific paths.
- Do not commit real proxy links or local sing-box binaries.
- Confirm generated artifacts remain ignored by `.gitignore`.

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
- Download the release archives and confirm they unzip cleanly.
- Launch the app on a test Mac.
- Open the menu bar window and check import, save profile, settings, logs, and
  quit actions.
