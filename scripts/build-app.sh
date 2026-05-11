#!/usr/bin/env bash
# scripts/build-app.sh — build the executable and assemble a Timesheet Tracker.app
# bundle in ./build/.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="TimesheetTracker"
BUNDLE_NAME="Timesheet Tracker.app"
BUILD_DIR="build"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Build failed: $BIN_PATH not found" >&2
    exit 1
fi

APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Built $APP_DIR"
echo "  Run it:   open \"$APP_DIR\""
echo "  Install:  cp -R \"$APP_DIR\" /Applications/"
