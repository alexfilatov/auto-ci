#!/bin/bash
# Build AutoCI.app — a menubar agent bundle around the AutoCIApp executable.
# Bakes a sane PATH into LSEnvironment so the GUI app can find git/gh/claude
# when launched from Finder/login-item (GUI apps don't inherit your shell PATH).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AutoCI"
BUNDLE_ID="com.alexfilatov.autoci"
APP_DIR="${APP_NAME}.app"
TOOL_PATH="/opt/homebrew/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# Set AUTOCI_SWIFT_FLAGS="--arch arm64 --arch x86_64" to build a universal binary for releases.
SWIFT_FLAGS="${AUTOCI_SWIFT_FLAGS:-}"

echo "==> Building release binary"
swift build -c release $SWIFT_FLAGS --product AutoCIApp

BIN_PATH="$(swift build -c release $SWIFT_FLAGS --product AutoCIApp --show-bin-path)/AutoCIApp"

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/AutoCIApp"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Auto-CI</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>AutoCIApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSEnvironment</key>
    <dict>
        <key>PATH</key><string>${TOOL_PATH}</string>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc codesign so notifications + persistence behave on modern macOS.
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || \
    echo "    (codesign skipped — app still runs unsigned)"

echo "==> Done: ${PWD}/${APP_DIR}"
echo "    Launch with: open ./${APP_DIR}"
