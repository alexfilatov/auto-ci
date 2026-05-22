#!/bin/bash
# One-shot installer: build the menubar app + CLI from source and install them.
#   - AutoCI.app  -> /Applications  (launched immediately; registers itself at login)
#   - auto-ci CLI -> /usr/local/bin (if writable) so `auto-ci init` works anywhere
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building CLI (release)"
swift build -c release

echo "==> Building AutoCI.app bundle"
./scripts/build-app.sh >/dev/null

echo "==> Installing AutoCI.app to /Applications"
rm -rf /Applications/AutoCI.app
cp -R AutoCI.app /Applications/AutoCI.app

CLI="$(swift build -c release --show-bin-path)/auto-ci"
if [ -w /usr/local/bin ] || mkdir -p /usr/local/bin 2>/dev/null && [ -w /usr/local/bin ]; then
    cp "$CLI" /usr/local/bin/auto-ci
    echo "==> Installed CLI to /usr/local/bin/auto-ci"
else
    echo "==> /usr/local/bin not writable. Install the CLI manually with:"
    echo "      sudo cp \"$CLI\" /usr/local/bin/auto-ci"
fi

echo "==> Launching AutoCI.app"
open /Applications/AutoCI.app

echo ""
echo "Done. Look for the 🔧 Auto-CI icon in your menu bar."
echo "Next: run 'auto-ci doctor' to verify gh/claude, then 'auto-ci init' inside a repo."
