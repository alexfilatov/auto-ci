#!/bin/bash
# Build universal (arm64 + Intel) release artifacts and publish a GitHub Release.
#   ./scripts/release.sh v0.1.0
# Requires: Xcode/Swift, gh (authenticated with repo access).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version-tag>  e.g. v0.1.0}"
ARCHS="--arch arm64 --arch x86_64"

echo "==> Building universal CLI + app ($VERSION)"
swift build -c release $ARCHS
AUTOCI_SWIFT_FLAGS="$ARCHS" ./scripts/build-app.sh >/dev/null

BIN="$(swift build -c release $ARCHS --show-bin-path)"

echo "==> Packaging artifacts"
rm -rf dist && mkdir -p dist
# ditto produces a macOS-correct zip preserving the bundle + symlinks.
ditto -c -k --keepParent AutoCI.app dist/AutoCI.app.zip
cp "$BIN/auto-ci" dist/auto-ci

echo "==> Verifying universality"
file dist/auto-ci | sed 's/^/    /'

echo "==> Creating GitHub Release $VERSION"
gh release create "$VERSION" \
    dist/AutoCI.app.zip dist/auto-ci \
    --title "Auto-CI $VERSION" \
    --notes "Prebuilt universal (Apple Silicon + Intel) binaries. No Xcode required.

Install:
\`\`\`
curl -fsSL https://raw.githubusercontent.com/alexfilatov/auto-ci/main/install.sh | bash
\`\`\`
The installer downloads these artifacts, strips the Gatekeeper quarantine flag, installs AutoCI.app to /Applications and the auto-ci CLI to your PATH, and launches the app."

echo "==> Done. Latest-download URLs:"
echo "    https://github.com/alexfilatov/auto-ci/releases/latest/download/AutoCI.app.zip"
echo "    https://github.com/alexfilatov/auto-ci/releases/latest/download/auto-ci"
