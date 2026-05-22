#!/bin/bash
# Build universal (arm64 + Intel) release artifacts and publish a GitHub Release.
#   ./scripts/release.sh v0.1.0
# Requires: Xcode/Swift, gh (authenticated with repo access).
#
# NOTARIZATION (optional, recommended): if a "Developer ID Application" certificate
# and a stored notary profile are present, the app is signed with a hardened
# runtime, notarized, and stapled — so it opens with zero Gatekeeper warnings.
# One-time setup:
#   1. Xcode ▸ Settings ▸ Accounts ▸ <team> ▸ Manage Certificates ▸ + ▸ Developer ID Application
#   2. Create an app-specific password at appleid.apple.com
#   3. xcrun notarytool store-credentials autoci-notary \
#        --apple-id "<you@example.com>" --team-id "<TEAMID>" --password "<app-specific-pw>"
# Without these, the script ships an ad-hoc-signed build (Gatekeeper warns; the
# installer strips quarantine to compensate).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version-tag>  e.g. v0.1.0}"
ARCHS="--arch arm64 --arch x86_64"

NOTARY_PROFILE="${AUTOCI_NOTARY_PROFILE:-autoci-notary}"

echo "==> Building universal CLI + app ($VERSION)"
swift build -c release $ARCHS
AUTOCI_SWIFT_FLAGS="$ARCHS" ./scripts/build-app.sh >/dev/null

BIN="$(swift build -c release $ARCHS --show-bin-path)"

# --- Sign + notarize when a Developer ID is available; otherwise ship ad-hoc. ---
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o 'Developer ID Application: [^"]*' | head -1 || true)"

if [ -n "$DEV_ID" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Signing with: $DEV_ID"
    codesign --force --deep --options runtime --timestamp \
        --sign "$DEV_ID" AutoCI.app
    codesign --force --options runtime --timestamp --sign "$DEV_ID" "$BIN/auto-ci"

    echo "==> Notarizing (this can take a few minutes)…"
    ditto -c -k --keepParent AutoCI.app /tmp/AutoCI-notarize.zip
    xcrun notarytool submit /tmp/AutoCI-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling"
    xcrun stapler staple AutoCI.app
    SIGNED=1
else
    echo "==> No Developer ID + notary profile found — shipping AD-HOC signed (Gatekeeper will warn)."
    echo "    Set up notarization: see scripts/release.sh header / README."
    SIGNED=0
fi

echo "==> Packaging artifacts"
rm -rf dist && mkdir -p dist
# ditto produces a macOS-correct zip preserving the bundle + symlinks.
ditto -c -k --keepParent AutoCI.app dist/AutoCI.app.zip
cp "$BIN/auto-ci" dist/auto-ci

echo "==> Verifying universality"
file dist/auto-ci | sed 's/^/    /'

SIGN_NOTE=$([ "$SIGNED" = "1" ] && echo "Signed with Developer ID and notarized — opens with no Gatekeeper warning." || echo "Ad-hoc signed (the installer strips the Gatekeeper quarantine flag).")

echo "==> Creating GitHub Release $VERSION"
gh release create "$VERSION" \
    dist/AutoCI.app.zip dist/auto-ci \
    --title "Auto-CI $VERSION" \
    --notes "Prebuilt universal (Apple Silicon + Intel) binaries. No Xcode required.
$SIGN_NOTE

Install:
\`\`\`
curl -fsSL https://raw.githubusercontent.com/alexfilatov/auto-ci/main/install.sh | bash
\`\`\`
The installer downloads these artifacts, strips the Gatekeeper quarantine flag, installs AutoCI.app to /Applications and the auto-ci CLI to your PATH, and launches the app."

echo "==> Done. Latest-download URLs:"
echo "    https://github.com/alexfilatov/auto-ci/releases/latest/download/AutoCI.app.zip"
echo "    https://github.com/alexfilatov/auto-ci/releases/latest/download/auto-ci"
