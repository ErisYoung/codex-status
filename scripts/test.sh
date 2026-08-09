#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ALT_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk"

swift_build() {
    local log
    log="$(mktemp -t codex-status-test)"
    if swift build -Xswiftc -enable-testing --product CodexStatusCoreTestsRunner 2>"$log"; then
        rm -f "$log"
        return 0
    fi
    if grep -q "SDK is not supported by the compiler" "$log" && [ -d "$ALT_SDK" ]; then
        echo "SDK/compiler mismatch detected, retrying with MacOSX14.5.sdk..."
        rm -f "$log"
        SDKROOT="$ALT_SDK" swift build -Xswiftc -enable-testing --product CodexStatusCoreTestsRunner
        return $?
    fi
    cat "$log" >&2
    rm -f "$log"
    return 1
}

swift_build

BIN_PATH="$(swift build --show-bin-path)/CodexStatusCoreTestsRunner"
"$BIN_PATH"
