#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox -c release
app="build/CampusBar.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/CampusBar "$app/Contents/MacOS/CampusBar"
cp Info.plist "$app/Contents/Info.plist"
printf 'Built %s\n' "$app"
