#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="${APP_OUTPUT:-../veil.app}"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-}"

echo "🔨 Сборка veil.app..."
rm -rf "$APP"
rm -rf "$APP/Contents/_CodeSignature"
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
    echo "📦 Скачивание sing-box ($SB_ARCH)..."
    TARBALL="sing-box-${SB_VERSION}-${SB_ARCH}.tar.gz"
    URL="https://github.com/SagerNet/sing-box/releases/download/${SB_TAG}/${TARBALL}"

    if [ "$SB_ARCH" = "darwin-arm64" ]; then
        EXPECTED_SHA256="$SB_SHA256_ARM64"
    else
        EXPECTED_SHA256="$SB_SHA256_AMD64"
    fi

    echo "   Версия: $SB_TAG  →  $URL"
    curl -fsSL "$URL" -o /tmp/singbox.tar.gz

    # Verify SHA256 checksum
    ACTUAL_SHA256=$(shasum -a 256 /tmp/singbox.tar.gz | awk '{print $1}')
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "   ❌ SHA256 не совпадает!"
        echo "      ожидалось: $EXPECTED_SHA256"
        echo "      получено:  $ACTUAL_SHA256"
        rm -f /tmp/singbox.tar.gz
        exit 1
    fi
    echo "   ✅ SHA256 проверена"

    tar -xzf /tmp/singbox.tar.gz -C /tmp --strip-components=1 \
        "sing-box-${SB_VERSION}-${SB_ARCH}/sing-box"
    mv /tmp/sing-box "$SB_BINARY"
    chmod +x "$SB_BINARY"
    rm /tmp/singbox.tar.gz
    echo "   ✅ sing-box $SB_TAG установлен в bundle"
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
    ProxyParser.swift \
    LanguageManager.swift \
    ThemeManager.swift \
    ToastManager.swift \
    ProfileManager.swift \
    VPNManager.swift \
    ContentView.swift \
    VeilApp.swift \
    -o "$MACOS/veil"

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
sign_path "$MACOS/veil"
sign_path "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "✅ Готово: $APP"
echo "   $(du -sh "$APP" | cut -f1)  (arch=$BUILD_ARCH, включая sing-box)"

# ── 4. Запуск (не в CI) ───────────────────────────────────────────────────────
if [ -z "$CI" ]; then
    echo "🚀 Запуск..."
    open "$APP"
fi
