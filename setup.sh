#!/bin/bash
# ============================================================
# Plexathon Setup Script
# ============================================================
# Guides you through first-time setup of the media stack.
# Safe to re-run if something went wrong the first time.
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "${BLUE}→${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
fail() { echo -e "${RED}✗ ERROR:${RESET} $*"; exit 1; }
header() { echo -e "\n${BOLD}$*${RESET}"; }

# ============================================================
header "Welcome to Plexathon Setup"
# ============================================================
echo ""
echo "This script will set up your personal media server."
echo "It should take about 10-15 minutes."
echo ""
read -p "Press Enter to begin..."

# ============================================================
header "Step 1 of 5 — Checking Requirements"
# ============================================================

if [[ "$(uname)" != "Darwin" ]]; then
  fail "This setup is designed for macOS (Mac mini). Detected: $(uname)"
fi
ok "Running on macOS"

if ! command -v docker &>/dev/null; then
  fail "Docker Desktop is not installed.\n  Download it at: https://www.docker.com/products/docker-desktop/\n  Then re-run this script."
fi
if ! docker info &>/dev/null 2>&1; then
  fail "Docker Desktop is installed but not running.\n  Open Docker Desktop from your Applications folder, wait for it to start, then re-run this script."
fi
ok "Docker Desktop is running"

if ! command -v docker-compose &>/dev/null; then
  fail "docker-compose not found. Make sure Docker Desktop is fully installed and up to date."
fi
ok "docker-compose is available"

# ============================================================
header "Step 2 of 5 — Configuration"
# ============================================================

if [[ ! -f .env ]]; then
  cp .env.example .env
  warn ".env file created from template. Please fill it in now."
  echo ""
  echo "Opening .env in TextEdit. Fill in:"
  echo "  • Your Windows laptop's IP address"
  echo "  • Your Windows username and password"
  echo "  • Your Plex claim token (get one at https://www.plex.tv/claim/)"
  echo ""
  echo "Save the file and come back here when done."
  echo ""
  open -e .env
  read -p "Press Enter once you've saved your .env file..."
fi

set -a; source .env; set +a

REQUIRED_VARS=(TIMEZONE MEDIA_PATH SMB_SERVER SMB_SHARE SMB_USERNAME SMB_PASSWORD PLEX_CLAIM)
MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  val="${!var:-}"
  if [[ -z "$val" || "$val" == *"your_"* || "$val" == *"xxxx"* || "$val" == *"yourdomain"* ]]; then
    MISSING+=("$var")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  fail "These values in .env still look like placeholders:\n  ${MISSING[*]}\n\n  Please edit .env and fill them in, then re-run setup."
fi
ok "Configuration looks good"

# ============================================================
header "Step 3 of 5 — Mounting Network Share"
# ============================================================

./scripts/mount-network-share.sh mount

# ============================================================
header "Step 4 of 5 — Creating Service Configs"
# ============================================================

if [[ ! -f ./filebrowser/config.json ]]; then
  cat > ./filebrowser/config.json << 'EOF'
{
  "port": 80,
  "baseURL": "",
  "address": "",
  "log": "stdout",
  "database": "/database.db",
  "root": "/srv"
}
EOF
  ok "FileBrowser config created"
fi

touch ./filebrowser/database.db

if [[ ! -f ./homepage/services.yaml ]]; then
  cat > ./homepage/services.yaml << 'EOF'
- Media:
    - Plex:
        href: http://localhost:32400/web
        description: Movies & TV
        icon: plex.png
    - Audiobookshelf:
        href: http://localhost:13378
        description: Audiobooks & Podcasts
        icon: audiobookshelf.png

- Tools:
    - FileBrowser:
        href: http://localhost:8080
        description: Manage Files
        icon: filebrowser.png
EOF
  ok "Homepage services config created"
fi

if [[ ! -f ./homepage/settings.yaml ]]; then
  cat > ./homepage/settings.yaml << 'EOF'
title: Plexathon
background: https://images.unsplash.com/photo-1489599849927-2ee91cede3ba
backgroundBlur: sm
cardBlur: md
theme: dark
color: slate
EOF
  ok "Homepage settings config created"
fi

ok "All service configs ready"

# ============================================================
header "Step 5 of 5 — Starting Services"
# ============================================================

# Check if Cloudflare tunnel is configured
if [[ ! -f ./cloudflared/config.yml ]]; then
  warn "Cloudflare tunnel is not configured yet."
  warn "Services will start without remote access."
  echo ""
  echo "  To set up remote access later, run:"
  echo "  ./scripts/setup-cloudflare-tunnel.sh"
  echo ""
  # Start without cloudflared (it will fail without its config)
  info "Pulling latest container images..."
  docker-compose pull audiobookshelf filebrowser homepage plex
  info "Starting services..."
  docker-compose up -d audiobookshelf filebrowser homepage plex
else
  info "Pulling latest container images..."
  docker-compose pull
  info "Starting services..."
  docker-compose up -d
fi

sleep 5

# Check services are running
FAILED=()
for service in plex audiobookshelf filebrowser homepage; do
  STATUS=$(docker inspect --format='{{.State.Status}}' "$service" 2>/dev/null || echo "missing")
  if [[ "$STATUS" != "running" ]]; then
    FAILED+=("$service ($STATUS)")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  warn "Some services didn't start cleanly: ${FAILED[*]}"
  warn "Check logs with: docker-compose logs -f"
else
  ok "All services are running"
fi

# ============================================================
echo ""
echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
echo ""
echo "Your services are available on your home network:"
echo ""
echo -e "  ${BOLD}Plex${RESET}             http://localhost:32400/web"
echo -e "  ${BOLD}Audiobookshelf${RESET}   http://localhost:13378"
echo -e "  ${BOLD}FileBrowser${RESET}      http://localhost:8080"
echo -e "  ${BOLD}Dashboard${RESET}        http://localhost:3000"
echo ""
echo -e "${YELLOW}First-time steps:${RESET}"
echo "  1. Open Plex and sign in with your Plex account"
echo "  2. Add your media libraries in Plex (movies, TV shows)"
echo "  3. Change the FileBrowser password (default: admin / admin)"
echo ""
if [[ ! -f ./cloudflared/config.yml ]]; then
  echo "To set up remote access from anywhere, run:"
  echo "  ./scripts/setup-cloudflare-tunnel.sh"
  echo ""
fi
