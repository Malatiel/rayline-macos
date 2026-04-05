#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="../veil.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "🔨 Сборка veil.app..."
mkdir -p "$MACOS" "$RES"
cp Info.plist "$APP/Contents/"

# ── 1. Архитектура ────────────────────────────────────────────────────────────
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macosx13.0"
    SB_ARCH="darwin-arm64"
else
    TARGET="x86_64-apple-macosx13.0"
    SB_ARCH="darwin-amd64"
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

echo "✅ Готово: $APP"
echo "   $(du -sh "$APP" | cut -f1)  (включая sing-box)"

# ── 4. Запуск (не в CI) ───────────────────────────────────────────────────────
if [ -z "$CI" ]; then
    echo "🚀 Запуск..."
    open "$APP"
fi
