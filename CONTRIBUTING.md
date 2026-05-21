# Contributing

Thanks for helping make Veil safer and more useful.

## Ground Rules

- Do not commit real proxy links, credentials, private keys, Apple signing
  certificates, personal logs, or machine-specific paths.
- Keep tests in the same style as the existing Swift XCTest files.
- The main app is SwiftUI plus sing-box. C++ code is legacy/experimental R&D;
  update C++ tests only when touching that legacy tree while it remains in the
  repository.
- Security-sensitive changes should be small, reviewable, and documented.
- Avoid adding dependencies unless the benefit is clear and the license is
  compatible with MIT.

## Local Checks

Run Swift tests:

```bash
swift test
```

Run C++ legacy tests when touching `src/` or C++ test files:

```bash
cmake -B cmake-build-debug
cmake --build cmake-build-debug
ctest --test-dir cmake-build-debug -V
```

Before opening a pull request, also scan the diff for personal data:

```bash
git diff --check
bash scripts/privacy_scan.sh
```

The scan intentionally allows documented examples in contributor and release
guidance. Review any reported match before pushing.

## Pull Request Checklist

- tests added or updated for behavior changes;
- `swift test` passes;
- C++ tests pass with CMake/CTest when C++ legacy code is touched;
- no real credentials, logs, certificates, or personal paths are committed;
- README, SECURITY, or PRIVACY docs updated when behavior changes.

## Releases

Release preparation is tracked in [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).
Do not publish release tags until local tests, privacy review, and generated
artifact checks are complete.
