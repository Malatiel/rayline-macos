#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  scripts/verify_release_artifact.sh <archive.zip> [archive.zip.sha256]

Environment:
  EXPECTED_VERSION  Optional CFBundleShortVersionString value to verify.
  EXPECTED_BUILD    Optional CFBundleVersion value to verify.

Checks:
  - SHA256 checksum verifies with shasum -a 256 -c
  - archive contains exactly one .app bundle
  - Info.plist is present and readable
  - Contents/MacOS/veil exists and is executable
  - Contents/MacOS/sing-box exists and is executable
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage >&2
    exit 64
fi

ARCHIVE="$1"
CHECKSUM="${2:-$ARCHIVE.sha256}"

if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: archive not found: $ARCHIVE" >&2
    exit 66
fi

if [ ! -f "$CHECKSUM" ]; then
    echo "ERROR: checksum not found: $CHECKSUM" >&2
    exit 66
fi

ARCHIVE_DIR="$(cd "$(dirname "$ARCHIVE")" && pwd)"
ARCHIVE_BASENAME="$(basename "$ARCHIVE")"
CHECKSUM_DIR="$(cd "$(dirname "$CHECKSUM")" && pwd)"
CHECKSUM_BASENAME="$(basename "$CHECKSUM")"

if [ "$ARCHIVE_DIR" != "$CHECKSUM_DIR" ]; then
    echo "ERROR: archive and checksum must be in the same directory" >&2
    exit 65
fi

echo "Verifying checksum: $CHECKSUM_BASENAME"
(
    cd "$ARCHIVE_DIR"
    shasum -a 256 -c "$CHECKSUM_BASENAME"
)

TMPDIR_VERIFY="$(mktemp -d "${TMPDIR:-/tmp}/veil-release-verify.XXXXXX")"
cleanup() {
    rm -rf "$TMPDIR_VERIFY"
}
trap cleanup EXIT

echo "Extracting archive: $ARCHIVE_BASENAME"
ditto -x -k "$ARCHIVE" "$TMPDIR_VERIFY"

APP_PATHS="$(find "$TMPDIR_VERIFY" -maxdepth 2 -name '*.app' -type d -print)"
APP_COUNT="$(printf '%s\n' "$APP_PATHS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$APP_COUNT" != "1" ]; then
    echo "ERROR: expected exactly one .app bundle, found $APP_COUNT" >&2
    printf '%s\n' "$APP_PATHS" >&2
    exit 65
fi

APP_PATH="$APP_PATHS"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VEIL_BIN="$APP_PATH/Contents/MacOS/veil"
SING_BOX_BIN="$APP_PATH/Contents/MacOS/sing-box"

if [ ! -f "$INFO_PLIST" ]; then
    echo "ERROR: missing Info.plist: $INFO_PLIST" >&2
    exit 65
fi

if [ ! -x "$VEIL_BIN" ]; then
    echo "ERROR: veil binary is missing or not executable: $VEIL_BIN" >&2
    exit 65
fi

if [ ! -x "$SING_BOX_BIN" ]; then
    echo "ERROR: sing-box binary is missing or not executable: $SING_BOX_BIN" >&2
    exit 65
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleVersion' "$INFO_PLIST")"

if [ -n "${EXPECTED_VERSION:-}" ] && [ "$VERSION" != "$EXPECTED_VERSION" ]; then
    echo "ERROR: expected version $EXPECTED_VERSION, got $VERSION" >&2
    exit 65
fi

if [ -n "${EXPECTED_BUILD:-}" ] && [ "$BUILD" != "$EXPECTED_BUILD" ]; then
    echo "ERROR: expected build $EXPECTED_BUILD, got $BUILD" >&2
    exit 65
fi

echo "App: $(basename "$APP_PATH")"
echo "Version: $VERSION ($BUILD)"
echo "veil: $(file "$VEIL_BIN")"
echo "sing-box: $("$SING_BOX_BIN" version 2>/dev/null | head -1 || file "$SING_BOX_BIN")"
echo "Release artifact OK"
