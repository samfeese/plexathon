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
header "Step 1 of 4 — Checking Requirements"
# ============================================================

if [[ "$(uname)" != "Darwin" ]]; then
  fail "This setup is designed for macOS (Mac mini). Detected: $(uname)"
fi
ok "Running on macOS"

# Detect container runtime: prefer podman, fall back to docker
if command -v podman &>/dev/null && podman info &>/dev/null 2>&1; then
  RUNTIME=podman
  ok "Podman is running"
  # Detect Podman socket for Homepage status badges
  PODMAN_SOCK=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || echo "")
  if [[ -n "$PODMAN_SOCK" ]]; then
    export DOCKER_SOCK="$PODMAN_SOCK"
    ok "Podman socket: $PODMAN_SOCK"
  fi
elif command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  RUNTIME=docker
  ok "Docker is running"
else
  fail "Neither Podman nor Docker Desktop is running.\n  Install Podman: brew install podman\n  Or Docker Desktop: https://www.docker.com/products/docker-desktop/"
fi

# Detect compose command
if command -v podman-compose &>/dev/null; then
  COMPOSE_CMD="podman-compose"
elif [[ "$RUNTIME" == "podman" ]] && podman compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="podman compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
else
  fail "No compose tool found. Install with: brew install podman-compose"
fi
ok "Compose command: $COMPOSE_CMD"

# ============================================================
header "Step 2 of 4 — Configuration"
# ============================================================

if [[ ! -f .env ]]; then
  cp .env.example .env
  warn ".env file created from template."
  echo ""
  echo "Opening .env in TextEdit. Fill in:"
  echo "  • MEDIA_PATH — the path to your external drive (e.g. /Volumes/MediaDrive)"
  echo "  • DOMAIN — your domain name (or leave as-is for local-only access)"
  echo "  • PLEX_CLAIM — your Plex claim token from https://www.plex.tv/claim/"
  echo "  • PROTONVPN_PRIVATE_KEY — your WireGuard private key from ProtonVPN"
  echo ""
  echo "Save the file and come back here when done."
  echo ""
  open -e .env
  read -p "Press Enter once you've saved your .env file..."
fi

set -a; source .env; set +a

REQUIRED_VARS=(TIMEZONE MEDIA_PATH PLEX_CLAIM)
MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  val="${!var:-}"
  if [[ -z "$val" || "$val" == *"your_"* || "$val" == *"xxxx"* || "$val" == *"yourdomain"* || "$val" == *"DriveName"* ]]; then
    MISSING+=("$var")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  fail "These values in .env are missing:\n  ${MISSING[*]}\n\n  Please edit .env and fill them in, then re-run setup."
fi
ok "Configuration looks good"

# Check external drive is accessible
if [[ ! -d "$MEDIA_PATH" ]]; then
  fail "Media path not found: $MEDIA_PATH\n\n  Make sure your external drive is plugged in.\n  Check its name in Finder under 'Locations' — it should appear as /Volumes/<name>\n  Then update MEDIA_PATH in .env to match."
fi
ok "External drive found at $MEDIA_PATH"

# Check Docker has access to the drive (macOS requires explicit file sharing permission)
if ! docker run --rm -v "$MEDIA_PATH:/test" alpine ls /test &>/dev/null 2>&1; then
  warn "Docker can't access $MEDIA_PATH"
  echo ""
  echo "  You need to allow Docker to access your external drive:"
  echo "  1. Open Docker Desktop"
  echo "  2. Go to Settings → Resources → File Sharing"
  echo "  3. Add: $MEDIA_PATH"
  echo "  4. Click Apply & Restart"
  echo ""
  read -p "  Press Enter once you've done this and Docker has restarted..."
  if ! docker run --rm -v "$MEDIA_PATH:/test" alpine ls /test &>/dev/null 2>&1; then
    fail "Docker still can't access $MEDIA_PATH. Check the File Sharing setting above."
  fi
fi
ok "Docker can access external drive"

# ============================================================
header "Step 3 of 4 — Creating Service Configs"
# ============================================================

# Create media subdirectories on the drive if missing
for dir in movies tv audiobooks podcasts downloads; do
  if [[ ! -d "$MEDIA_PATH/$dir" ]]; then
    mkdir -p "$MEDIA_PATH/$dir"
    info "Created folder: $MEDIA_PATH/$dir"
  fi
done
ok "Media folders ready"

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
    - Jellyfin:
        href: http://localhost:8096
        description: Movies & TV
        icon: jellyfin.png
    - Audiobookshelf:
        href: http://localhost:13378
        description: Audiobooks & Podcasts
        icon: audiobookshelf.png

- Downloads:
    - qBittorrent:
        href: http://localhost:8090
        description: Torrents (via ProtonVPN)
        icon: qbittorrent.png

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
header "Step 4 of 4 — Starting Services"
# ============================================================

if [[ ! -f ./cloudflared/config.yml ]]; then
  warn "Cloudflare tunnel is not configured yet — starting without remote access."
  echo ""
  echo "  To set up remote access later, run:"
  echo "  ./scripts/setup-cloudflare-tunnel.sh"
  echo ""
  info "Pulling latest container images..."
  docker-compose pull plex audiobookshelf filebrowser homepage gluetun qbittorrent
  info "Starting services..."
  docker-compose up -d plex audiobookshelf filebrowser homepage gluetun qbittorrent
else
  info "Pulling latest container images..."
  $COMPOSE_CMD pull
  info "Starting services..."
  $COMPOSE_CMD up -d
fi

sleep 5

FAILED=()
for service in jellyfin audiobookshelf filebrowser homepage; do
  STATUS=$($RUNTIME inspect --format='{{.State.Status}}' "$service" 2>/dev/null || echo "missing")
  if [[ "$STATUS" != "running" ]]; then
    FAILED+=("$service ($STATUS)")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  warn "Some services didn't start cleanly: ${FAILED[*]}"
  warn "Check logs with: $COMPOSE_CMD logs -f"
else
  ok "All services are running"
fi

# ============================================================
echo ""
echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
echo ""
echo "Your services are available on your home network:"
echo ""
echo -e "  ${BOLD}Jellyfin${RESET}         http://localhost:8096"
echo -e "  ${BOLD}Audiobookshelf${RESET}   http://localhost:13378"
echo -e "  ${BOLD}qBittorrent${RESET}      http://localhost:8090"
echo -e "  ${BOLD}FileBrowser${RESET}      http://localhost:8080"
echo -e "  ${BOLD}Dashboard${RESET}        http://localhost:3000"
echo ""
echo -e "${YELLOW}First-time steps:${RESET}"
echo "  1. Open Plex and sign in with your Plex account"
echo "  2. Add media libraries in Plex:"
echo "     Movies → /media/movies"
echo "     TV     → /media/tv"
echo "  3. Check qBittorrent logs for its temporary password:"
echo "     docker-compose logs qbittorrent | grep -i password"
echo "  4. Change the FileBrowser password (default: admin / admin)"
echo ""
if [[ ! -f ./cloudflared/config.yml ]]; then
  echo "To set up remote access from anywhere, run:"
  echo "  ./scripts/setup-cloudflare-tunnel.sh"
  echo ""
fi
