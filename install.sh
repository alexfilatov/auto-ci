#!/bin/bash
# Auto-CI installer.
#
#   curl -fsSL https://raw.githubusercontent.com/alexfilatov/auto-ci/main/install.sh | bash
#
# Tries prebuilt binaries first (no Xcode needed). If no release is available,
# falls back to building from source (requires Xcode/Swift).
set -euo pipefail

REPO="alexfilatov/auto-ci"
BASE="https://github.com/${REPO}/releases/latest/download"
SRC_DIR="${HOME}/.auto-ci/src"

step() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Auto-CI is macOS-only."

# Pick the first writable bin dir for the CLI.
cli_dir() {
    for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [ -d "$d" ] && [ -w "$d" ]; then echo "$d"; return; fi
    done
    mkdir -p "$HOME/.local/bin"; echo "$HOME/.local/bin"
}

install_prebuilt() {
    local tmp; tmp="$(mktemp -d)"
    step "Downloading prebuilt Auto-CI (no Xcode needed)…"
    if ! curl -fsSL "${BASE}/AutoCI.app.zip" -o "$tmp/AutoCI.app.zip"; then
        rm -rf "$tmp"; return 1
    fi
    curl -fsSL "${BASE}/auto-ci" -o "$tmp/auto-ci" || { rm -rf "$tmp"; return 1; }
    ok "Downloaded latest release"

    step "Installing the menubar app"
    ditto -x -k "$tmp/AutoCI.app.zip" "$tmp/extracted"
    # Strip the Gatekeeper quarantine flag so the unsigned app opens cleanly.
    xattr -dr com.apple.quarantine "$tmp/extracted/AutoCI.app" 2>/dev/null || true
    rm -rf /Applications/AutoCI.app
    cp -R "$tmp/extracted/AutoCI.app" /Applications/AutoCI.app
    ok "AutoCI.app → /Applications"

    step "Installing the auto-ci command"
    local dir; dir="$(cli_dir)"
    cp "$tmp/auto-ci" "$dir/auto-ci"
    chmod +x "$dir/auto-ci"
    xattr -dr com.apple.quarantine "$dir/auto-ci" 2>/dev/null || true
    ok "auto-ci → $dir"
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) warn "Add it to your PATH:  echo 'export PATH=\"$dir:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
    esac

    rm -rf "$tmp"
    finish
}

install_from_source() {
    warn "No prebuilt release found — building from source (requires Xcode/Swift)."
    command -v git   >/dev/null 2>&1 || die "git is required. Install: xcode-select --install"
    command -v swift >/dev/null 2>&1 || die "swift is required. Install Xcode, then re-run."
    if [ -d "${SRC_DIR}/.git" ]; then
        step "Updating source at ${SRC_DIR}"
        git -C "${SRC_DIR}" fetch --quiet origin && git -C "${SRC_DIR}" reset --hard --quiet origin/main
    else
        step "Cloning into ${SRC_DIR}"
        mkdir -p "$(dirname "${SRC_DIR}")"
        git clone --quiet "https://github.com/${REPO}.git" "${SRC_DIR}"
    fi
    exec bash "${SRC_DIR}/scripts/install.sh"
}

finish() {
    step "Launching Auto-CI"
    open /Applications/AutoCI.app
    ok "Running — look for the 🔧 icon in your menu bar (top-right)"
    cat <<EOF

🎉 Auto-CI is installed.

Next steps:
  auto-ci doctor          check that gh + claude are installed and signed in
  cd <your-repo>
  auto-ci init            start watching this repo

Then just 'git push' as usual — Auto-CI fixes failing CI on its own.
EOF
    exit 0
}

install_prebuilt || install_from_source
