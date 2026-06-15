#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# AI Usage Counter — macOS / Linux setup script
# ─────────────────────────────────────────────────────────────────────────────
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✔${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✘${NC} $1"; exit 1; }
step() { echo -e "\n${BOLD}▸ $1${NC}"; }

echo -e "${BOLD}AI Usage Counter — Install Script${NC}"
echo "────────────────────────────────────"

# ── 1. Xcode Command Line Tools (macOS only) ─────────────────────────────────
if [[ "$OSTYPE" == "darwin"* ]]; then
  step "Checking Xcode Command Line Tools"
  if xcode-select -p &>/dev/null; then
    ok "Xcode CLT already installed ($(xcode-select -p))"
  else
    warn "Installing Xcode Command Line Tools — follow the popup..."
    xcode-select --install
    echo "   Re-run this script after the installation completes."
    exit 0
  fi
fi

# ── 2. Rust ───────────────────────────────────────────────────────────────────
step "Checking Rust"
if command -v rustc &>/dev/null; then
  ok "Rust $(rustc --version)"
else
  warn "Rust not found — installing via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  source "$HOME/.cargo/env"
  ok "Rust installed: $(rustc --version)"
fi

# Make sure cargo is on PATH for this session
export PATH="$HOME/.cargo/bin:$PATH"

# ── 3. Node.js ────────────────────────────────────────────────────────────────
step "Checking Node.js"
if command -v node &>/dev/null; then
  ok "Node.js $(node --version) / npm $(npm --version)"
else
  fail "Node.js not found.\n   macOS: brew install node\n   Or download from https://nodejs.org"
fi

# ── 4. npm install ────────────────────────────────────────────────────────────
step "Installing npm dependencies"
cd "$(dirname "$0")"
npm install
ok "npm packages installed"

# ── 5. Tauri icons ───────────────────────────────────────────────────────────
step "Generating app icons"
if [ -f "../icon.png" ]; then
  npm run tauri icon ../icon.png
  ok "Icons generated from ../icon.png"
else
  warn "icon.png not found at project root — skipping icon generation"
  warn "Run manually: npm run tauri icon <path-to-icon.png>"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}Setup complete!${NC}"
echo "────────────────────────────────────"
echo "  Dev mode : npm run tauri dev"
echo "  Build    : npm run tauri build"
echo ""
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "  Built app → src-tauri/target/release/bundle/macos/"
else
  echo "  Built app → src-tauri/target/release/bundle/"
fi
