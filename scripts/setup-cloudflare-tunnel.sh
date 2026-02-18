#!/bin/bash
# ============================================================
# setup-cloudflare-tunnel.sh
# Sets up Cloudflare Tunnel for secure remote access
# ============================================================
# Run this after initial setup to access your media from anywhere.
# Traffic flow: Internet → Cloudflare → this tunnel → containers
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ok()     { echo -e "${GREEN}✓${RESET} $*"; }
info()   { echo -e "${BLUE}→${RESET} $*"; }
warn()   { echo -e "${YELLOW}!${RESET} $*"; }
fail()   { echo -e "${RED}✗ ERROR:${RESET} $*"; exit 1; }
header() { echo -e "\n${BOLD}$*${RESET}"; }
pause()  { read -p "  Press Enter to continue..."; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
CLOUDFLARED_DIR="$SCRIPT_DIR/../cloudflared"

if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env not found. Run ./setup.sh first."
fi
set -a; source "$ENV_FILE"; set +a

# ============================================================
header "Cloudflare Tunnel Setup"
# ============================================================
echo ""
echo "This sets up secure remote access to your media server."
echo "Cloudflare handles SSL certificates automatically — nothing to manage."
echo ""
echo "You'll need:"
echo "  • A domain name (e.g. myfamily.com) — ~\$10/year"
echo "  • A free Cloudflare account managing that domain"
echo ""
echo "If you don't have these yet:"
echo "  Sign up:     https://www.cloudflare.com/"
echo "  Buy domain:  https://www.cloudflare.com/products/registrar/"
echo ""
read -p "Ready? Press Enter to continue (or Ctrl+C to cancel)..."

# ============================================================
header "Step 1 — Install cloudflared"
# ============================================================

if command -v cloudflared &>/dev/null; then
  ok "cloudflared already installed ($(cloudflared --version 2>&1 | head -1))"
else
  if ! command -v brew &>/dev/null; then
    fail "Homebrew is not installed.\n  Install it: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  fi
  info "Installing cloudflared via Homebrew..."
  brew install cloudflare/cloudflare/cloudflared
  ok "cloudflared installed"
fi

# ============================================================
header "Step 2 — Log in to Cloudflare"
# ============================================================

echo ""
echo "A browser window will open — log in and select your domain."
echo ""
pause
cloudflared tunnel login
ok "Logged in to Cloudflare"

# ============================================================
header "Step 3 — Create the Tunnel"
# ============================================================

echo ""
read -p "  Enter a name for your tunnel (e.g. home-media): " TUNNEL_NAME
TUNNEL_NAME="${TUNNEL_NAME:-home-media}"

info "Creating tunnel: $TUNNEL_NAME"
cloudflared tunnel create "$TUNNEL_NAME"

CREDENTIALS_FILE=$(ls ~/.cloudflared/*.json 2>/dev/null | head -1 || true)
if [[ -z "$CREDENTIALS_FILE" ]]; then
  fail "Tunnel credentials file not found in ~/.cloudflared/"
fi

TUNNEL_ID=$(basename "$CREDENTIALS_FILE" .json)
ok "Tunnel created (ID: $TUNNEL_ID)"

mkdir -p "$CLOUDFLARED_DIR"
cp "$CREDENTIALS_FILE" "$CLOUDFLARED_DIR/${TUNNEL_ID}.json"
ok "Credentials saved to cloudflared/${TUNNEL_ID}.json"

# ============================================================
header "Step 4 — Enter Your Domain"
# ============================================================

echo ""
if [[ -z "${DOMAIN:-}" || "$DOMAIN" == "yourdomain.com" ]]; then
  read -p "  Enter your domain name (e.g. myfamily.com): " DOMAIN
  sed -i '' "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" "$ENV_FILE"
  ok "Domain saved to .env"
fi

# ============================================================
header "Step 5 — Generate Tunnel Config"
# ============================================================

cat > "$CLOUDFLARED_DIR/config.yml" << EOF
# Plexathon - Cloudflare Tunnel Config
# Each hostname routes to the matching container.
# Cloudflare handles SSL — no certificates to configure.

tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: plex.${DOMAIN}
    service: http://localhost:32400
    # Plex uses network_mode: host, so reached via localhost

  - hostname: audiobooks.${DOMAIN}
    service: http://audiobookshelf:80

  - hostname: files.${DOMAIN}
    service: http://filebrowser:80

  - hostname: home.${DOMAIN}
    service: http://homepage:3000

  # Catch-all — must be last
  - service: http_status:404
EOF

ok "Tunnel config written to cloudflared/config.yml"

# ============================================================
header "Step 6 — Add DNS Records in Cloudflare"
# ============================================================

echo ""
echo "Now add DNS records so Cloudflare knows to route traffic to your tunnel."
echo ""
echo "  Go to: https://dash.cloudflare.com → ${DOMAIN} → DNS → Add record"
echo ""
echo "  Add these 4 records (copy/paste the Target exactly):"
echo ""
printf "  %-14s %-8s %-52s %-8s\n" "Name" "Type" "Target" "Proxy"
printf "  %-14s %-8s %-52s %-8s\n" "----" "----" "------" "-----"
printf "  %-14s %-8s %-52s %-8s\n" "plex"        "CNAME" "${TUNNEL_ID}.cfargotunnel.com" "ON (orange)"
printf "  %-14s %-8s %-52s %-8s\n" "audiobooks"  "CNAME" "${TUNNEL_ID}.cfargotunnel.com" "ON (orange)"
printf "  %-14s %-8s %-52s %-8s\n" "files"       "CNAME" "${TUNNEL_ID}.cfargotunnel.com" "ON (orange)"
printf "  %-14s %-8s %-52s %-8s\n" "home"        "CNAME" "${TUNNEL_ID}.cfargotunnel.com" "ON (orange)"
echo ""
echo "  Tip: 'Proxy status' must be ON (the cloud icon should be orange, not grey)."
echo "  This is what enables SSL and Cloudflare's protection."
echo ""
info "Come back here once you've added all 4 DNS records."
pause

# ============================================================
header "Step 7 — Start the Tunnel"
# ============================================================

info "Starting all services including Cloudflare tunnel..."
cd "$SCRIPT_DIR/.."
docker-compose up -d

sleep 5

STATUS=$(docker inspect --format='{{.State.Status}}' cloudflared 2>/dev/null || echo "not found")
if [[ "$STATUS" == "running" ]]; then
  ok "Cloudflare tunnel is running!"
else
  warn "Tunnel container status: $STATUS"
  warn "Check logs: docker-compose logs -f cloudflared"
fi

# ============================================================
echo ""
echo -e "${GREEN}${BOLD}Remote access setup complete!${RESET}"
echo ""
echo "Your services are now available from anywhere:"
echo ""
echo -e "  ${BOLD}Plex${RESET}             https://plex.${DOMAIN}"
echo -e "  ${BOLD}Audiobookshelf${RESET}   https://audiobooks.${DOMAIN}"
echo -e "  ${BOLD}FileBrowser${RESET}      https://files.${DOMAIN}"
echo -e "  ${BOLD}Dashboard${RESET}        https://home.${DOMAIN}"
echo ""
echo "DNS propagation can take a few minutes. If it doesn't work immediately, wait 5 minutes and try again."
echo ""
