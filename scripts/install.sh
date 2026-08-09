#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${CODEX_STATUS_APP_DIR:-$HOME/Applications/CodexStatus.app}"

"$ROOT_DIR/scripts/build.sh"
BIN_PATH="$(swift build -c release --show-bin-path)/CodexStatus"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/CodexStatus"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/.build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
chmod +x "$APP_DIR/Contents/MacOS/CodexStatus"
codesign --force -s - "$APP_DIR" 2>/dev/null || true

# Register with LaunchServices so the bundle proxy is resolvable (required by
# UNUserNotificationCenter and for reliable launches from the Finder).
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

printf 'Installed: %s\n' "$APP_DIR"
printf 'Launch with: open "%s"\n' "$APP_DIR"
