# Contributing

Thanks for helping make Veil safer and more useful.

## Ground Rules

- Do not commit real proxy links, credentials, private keys, Apple signing
  certificates, personal logs, or machine-specific paths.
- Keep tests in the same style as the existing Swift XCTest and C++ test files.
- New parser behavior should update both Swift and C++ coverage when applicable.
- Security-sensitive changes should be small, reviewable, and documented.
- Avoid adding dependencies unless the benefit is clear and the license is
  compatible with MIT.

## Local Checks

Run Swift tests:

```bash
swift test
```

Run C++ tests:

```bash
cmake -B cmake-build-debug
cmake --build cmake-build-debug
ctest --test-dir cmake-build-debug -V
```

Before opening a pull request, also scan the diff for personal data:

```bash
git diff --check
git grep -n -E 'BEGIN (RSA|OPENSSH|EC|DSA|PRIVATE) KEY|github_pat_|ghp_|sk-|/Users/|password|TOKEN|SECRET'
```

The pattern intentionally produces false positives for test fixtures and GitHub
Actions secret names. Review the matches before pushing.

## Pull Request Checklist

- tests added or updated for behavior changes;
- `swift test` passes;
- C++ tests pass with CMake/CTest;
- no real credentials, logs, certificates, or personal paths are committed;
- README, SECURITY, or PRIVACY docs updated when behavior changes.
