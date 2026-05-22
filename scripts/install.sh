#!/bin/bash
# Build the menubar app + CLI from source and install them:
#   - AutoCI.app  -> /Applications  (launched immediately; registers itself at login)
#   - auto-ci CLI -> first writable bin dir (/opt/homebrew/bin, /usr/local/bin, or ~/.local/bin)
set -euo pipefail

cd "$(dirname "$0")/.."

LOG="$(mktemp -t auto-ci-install)"
trap 'rm -f "$LOG"' EXIT

step() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$1"; }
fail() {
    printf '  \033[1;31m✗\033[0m %s\n' "$1" >&2
    printf '\n--- build log (last 30 lines) ---\n' >&2
    tail -30 "$LOG" >&2
    exit 1
}

step "Building Auto-CI from source (~30s)…"
# Quiet the build; harmless linker/search-path warnings stay in the log, not your terminal.
swift build -c release >"$LOG" 2>&1 || fail "CLI build failed."
ok "Built the auto-ci CLI"
./scripts/build-app.sh >>"$LOG" 2>&1 || fail "App bundle build failed."
ok "Built AutoCI.app"

step "Installing the menubar app"
rm -rf /Applications/AutoCI.app
cp -R AutoCI.app /Applications/AutoCI.app
ok "AutoCI.app → /Applications"

step "Installing the auto-ci command"
CLI="$(swift build -c release --show-bin-path 2>>"$LOG")/auto-ci"
install_dir=""
for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
    if [ -d "$d" ] && [ -w "$d" ]; then install_dir="$d"; break; fi
done
[ -n "$install_dir" ] || { mkdir -p "$HOME/.local/bin"; install_dir="$HOME/.local/bin"; }
cp "$CLI" "$install_dir/auto-ci"
ok "auto-ci → $install_dir"
case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) warn "Add it to your PATH:  echo 'export PATH=\"$install_dir:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac

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
