#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

patterns=(
  'AKIA[0-9A-Z]{16}'
  'ghp_[A-Za-z0-9_]{20,}'
  'github_pat_'
  'sk-[A-Za-z0-9_-]{20,}'
  'BEGIN (RSA|OPENSSH|EC|DSA|PRIVATE) KEY'
  '/Users/'
  '@gmail'
  '@icloud'
  '@mail'
  '@yandex'
)

allowlist=(
  'CONTRIBUTING.md:'
  'docs/RELEASE_CHECKLIST.md:'
)

regex="$(IFS='|'; echo "${patterns[*]}")"
matches="$(git grep -n -E "$regex" -- . ':!Tests/shared_test_cases.json' || true)"

if [[ -z "$matches" ]]; then
  echo "Privacy scan passed: no sensitive patterns found."
  exit 0
fi

filtered="$matches"
for allowed in "${allowlist[@]}"; do
  filtered="$(printf '%s\n' "$filtered" | grep -v -F "$allowed" || true)"
done

if [[ -z "$filtered" ]]; then
  echo "Privacy scan passed: only allowlisted documentation examples matched."
  exit 0
fi

echo "Privacy scan failed. Review these matches before committing:" >&2
printf '%s\n' "$filtered" >&2
exit 1
