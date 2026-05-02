#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/RsyncGUI.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$ROOT/Assets/AppIcon.iconset"
ICNS="$ROOT/Assets/AppIcon.icns"

cd "$ROOT"

swift build -c release

mkdir -p "$MACOS" "$RESOURCES" "$ROOT/Assets"

swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"

cp "$ROOT/.build/release/RsyncGUI" "$MACOS/RsyncGUI"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ICNS" "$RESOURCES/AppIcon.icns"

chmod +x "$MACOS/RsyncGUI"

echo "$APP"
