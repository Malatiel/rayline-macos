#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="${APP_OUTPUT:-../Rayline.app}"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-}"
SING_BOX_BINARY="${SING_BOX_BINARY:-}"
TMPDIR_BUILD=""

cleanup() {
    if [ -n "$TMPDIR_BUILD" ] && [ -d "$TMPDIR_BUILD" ]; then
        rm -rf "$TMPDIR_BUILD"
    fi
}
trap cleanup EXIT

echo "🔨 Сборка Rayline.app..."
rm -rf "$APP"
if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.provenance "$APP" 2>/dev/null || true
fi
mkdir -p "$MACOS" "$RES"
cp Info.plist "$APP/Contents/"

# ── 1. Архитектура ────────────────────────────────────────────────────────────
if [ "$BUILD_ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macosx13.0"
    SB_ARCH="darwin-arm64"
elif [ "$BUILD_ARCH" = "x86_64" ]; then
    TARGET="x86_64-apple-macosx13.0"
    SB_ARCH="darwin-amd64"
else
    echo "❌ Unsupported BUILD_ARCH: $BUILD_ARCH"
    exit 1
fi

# ── 2. Скачать sing-box (если ещё нет внутри .app) ───────────────────────────
# Pinned version and SHA256 checksums for supply-chain safety.
# To update: change SB_TAG, SB_VERSION, and the checksums from the official release.
SB_TAG="v1.11.4"
SB_VERSION="1.11.4"
SB_SHA256_ARM64="f4349633befd75c972a5a958cbfb6236a1e20b585425ae7c3ec73e5fa29217c5"
SB_SHA256_AMD64="ba5ee4d4630b6cb36c24f0f33d7f9b790b185eceebc74818ca6ff1283bd5e94b"

SB_BINARY="$MACOS/sing-box"
if [ ! -f "$SB_BINARY" ]; then
    if [ -n "$SING_BOX_BINARY" ]; then
        if [ ! -x "$SING_BOX_BINARY" ]; then
            echo "❌ SING_BOX_BINARY не найден или не исполняемый: $SING_BOX_BINARY"
            exit 1
        fi
        echo "📦 Использование локального sing-box: $SING_BOX_BINARY"
        cp "$SING_BOX_BINARY" "$SB_BINARY"
        chmod +x "$SB_BINARY"
        echo "   ✅ sing-box скопирован в bundle ($("$SB_BINARY" version 2>/dev/null | head -1))"
    else
        echo "📦 Скачивание sing-box ($SB_ARCH)..."
        TARBALL="sing-box-${SB_VERSION}-${SB_ARCH}.tar.gz"
        URL="https://github.com/SagerNet/sing-box/releases/download/${SB_TAG}/${TARBALL}"

        if [ "$SB_ARCH" = "darwin-arm64" ]; then
            EXPECTED_SHA256="$SB_SHA256_ARM64"
        else
            EXPECTED_SHA256="$SB_SHA256_AMD64"
        fi

        TMPDIR_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/rayline-build.XXXXXX")"
        ARCHIVE="$TMPDIR_BUILD/singbox.tar.gz"
        EXTRACT_DIR="$TMPDIR_BUILD/extract"
        mkdir -p "$EXTRACT_DIR"

        echo "   Версия: $SB_TAG  →  $URL"
        curl -fsSL "$URL" -o "$ARCHIVE"

        # Verify SHA256 checksum
        ACTUAL_SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
        if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
            echo "   ❌ SHA256 не совпадает!"
            echo "      ожидалось: $EXPECTED_SHA256"
            echo "      получено:  $ACTUAL_SHA256"
            exit 1
        fi
        echo "   ✅ SHA256 проверена"

        tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" --strip-components=1 \
            "sing-box-${SB_VERSION}-${SB_ARCH}/sing-box"
        mv "$EXTRACT_DIR/sing-box" "$SB_BINARY"
        chmod +x "$SB_BINARY"
        echo "   ✅ sing-box $SB_TAG установлен в bundle"
    fi
else
    echo "   ✅ sing-box уже в bundle ($(${SB_BINARY} version 2>/dev/null | head -1))"
fi

# ── 3. Компиляция Swift ───────────────────────────────────────────────────────
echo "🛠  Компиляция Swift..."
swiftc \
    -target "$TARGET" \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -framework CoreImage \
    *.swift \
    -o "$MACOS/rayline"

sign_path() {
    local path="$1"
    local args=(--force --sign "$SIGN_IDENTITY")
    if [ "$SIGN_IDENTITY" != "-" ]; then
        args+=(--timestamp --options runtime)
        if [ -n "$ENTITLEMENTS_PATH" ] && [ -f "$ENTITLEMENTS_PATH" ]; then
            args+=(--entitlements "$ENTITLEMENTS_PATH")
        fi
    fi
    codesign "${args[@]}" "$path"
}

echo "🔏 Подпись bundle..."
sign_path "$MACOS/sing-box"
sign_path "$MACOS/rayline"
sign_path "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "✅ Готово: $APP"
echo "   $(du -sh "$APP" | cut -f1)  (arch=$BUILD_ARCH, включая sing-box)"

# ── 4. Запуск (не в CI) ───────────────────────────────────────────────────────
if [ -z "$CI" ]; then
    echo "🚀 Запуск..."
    open "$APP"
fi
