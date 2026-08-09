#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ALT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk"

# This machine's CommandLineTools ships a compiler that is newer than its
# bundled SDK, which breaks `swift build`. Retry with an older SDK when that
# exact mismatch is detected so plain `./scripts/build.sh` just works.
swift_build() {
    local log
    log="$(mktemp -t codex-status-build)"
    if swift build -c release --product CodexStatus 2>"$log"; then
        rm -f "$log"
        return 0
    fi
    if grep -q "SDK is not supported by the compiler" "$log" && [ -d "$ALT_SDK" ]; then
        echo "SDK/compiler mismatch detected, retrying with MacOSX14.5.sdk..."
        rm -f "$log"
        SDKROOT="$ALT_SDK" swift build -c release --product CodexStatus
        return $?
    fi
    cat "$log" >&2
    rm -f "$log"
    return 1
}

swift_build

if [ ! -d "$ROOT_DIR/Assets/AppIcon.iconset" ]; then
    echo "Generating Assets/AppIcon.iconset..."
    if ! swift "$ROOT_DIR/scripts/make_icon.swift" 2>/tmp/codex-status-icon.log; then
        if grep -q "SDK is not supported by the compiler" /tmp/codex-status-icon.log && [ -d "$ALT_SDK" ]; then
            echo "Retrying icon generation with MacOSX14.5.sdk..."
            SDKROOT="$ALT_SDK" swift "$ROOT_DIR/scripts/make_icon.swift"
        else
            cat /tmp/codex-status-icon.log >&2
            exit 1
        fi
    fi
fi

ICON_PATH="$ROOT_DIR/.build/AppIcon.icns"
iconutil -c icns "$ROOT_DIR/Assets/AppIcon.iconset" -o "$ICON_PATH"

BIN_PATH="$(swift build -c release --show-bin-path)/CodexStatus"
printf 'Built: %s\n' "$BIN_PATH"
printf 'Icon: %s\n' "$ICON_PATH"
