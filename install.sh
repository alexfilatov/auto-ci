#!/bin/bash
# Remote bootstrap installer for Auto-CI.
#
#   curl -fsSL https://raw.githubusercontent.com/alexfilatov/auto-ci/main/install.sh | bash
#
# Clones (or updates) the repo into ~/.auto-ci/src, builds the CLI + menubar app
# from source, installs AutoCI.app to /Applications and the auto-ci CLI to
# /usr/local/bin, and launches the app.
set -euo pipefail

REPO_URL="https://github.com/alexfilatov/auto-ci.git"
SRC_DIR="${HOME}/.auto-ci/src"

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# --- Prerequisites (build-time) ---
command -v git >/dev/null 2>&1 || die "git is required. Install Xcode Command Line Tools: xcode-select --install"
if ! command -v swift >/dev/null 2>&1; then
    die "swift is required. Install Xcode from the App Store (or 'xcode-select --install'), then re-run."
fi

case "$(uname -s)" in
    Darwin) ;;
    *) die "Auto-CI is macOS-only." ;;
esac

# --- Fetch source ---
if [ -d "${SRC_DIR}/.git" ]; then
    say "Updating existing checkout at ${SRC_DIR}"
    git -C "${SRC_DIR}" fetch --quiet origin
    git -C "${SRC_DIR}" reset --hard --quiet origin/main
else
    say "Cloning ${REPO_URL} into ${SRC_DIR}"
    mkdir -p "$(dirname "${SRC_DIR}")"
    git clone --quiet "${REPO_URL}" "${SRC_DIR}"
fi

# --- Build + install (delegates to the in-repo installer) ---
say "Building and installing"
exec bash "${SRC_DIR}/scripts/install.sh"
