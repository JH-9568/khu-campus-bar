#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if pgrep -x CampusBar >/dev/null; then
    printf '%s\n' 'Quit CampusBar before rebuilding to preserve its Keychain identity.' >&2
    exit 1
else
    result=$?
    if [ "$result" -ne 1 ]; then
        printf '%s\n' 'Cannot verify whether CampusBar is running; build stopped.' >&2
        exit 1
    fi
fi
mkdir -p .build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox -c release
app="build/CampusBar.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/CampusBar "$app/Contents/MacOS/CampusBar"
cp Info.plist "$app/Contents/Info.plist"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/build-icons.swift
iconutil -c icns .build/CampusBar.iconset -o "$app/Contents/Resources/CampusBar.icns"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
