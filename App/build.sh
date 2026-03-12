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
SB_BINARY="$MACOS/sing-box"
if [ ! -f "$SB_BINARY" ]; then
    echo "📦 Скачивание sing-box ($SB_ARCH)..."
    LATEST=$(curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" \
             | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
    VERSION="${LATEST#v}"
    TARBALL="sing-box-${VERSION}-${SB_ARCH}.tar.gz"
    URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST}/${TARBALL}"

    echo "   Версия: $LATEST  →  $URL"
    curl -fsSL "$URL" -o /tmp/singbox.tar.gz
    tar -xzf /tmp/singbox.tar.gz -C /tmp --strip-components=1 \
        "sing-box-${VERSION}-${SB_ARCH}/sing-box"
    mv /tmp/sing-box "$SB_BINARY"
    chmod +x "$SB_BINARY"
    rm /tmp/singbox.tar.gz
    echo "   ✅ sing-box $LATEST установлен в bundle"
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
