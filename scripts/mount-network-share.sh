#!/bin/bash
# ============================================================
# mount-network-share.sh
# Mounts (or unmounts) the Windows SMB media share
# ============================================================
# Usage:
#   ./scripts/mount-network-share.sh mount    — mount the share
#   ./scripts/mount-network-share.sh unmount  — unmount
#   ./scripts/mount-network-share.sh status   — check if mounted
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "${BLUE}→${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
fail() { echo -e "${RED}✗ ERROR:${RESET} $*"; exit 1; }

# Load config from .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  fail ".env file not found at $ENV_FILE\n  Run setup first: ./setup.sh"
fi

set -a; source "$ENV_FILE"; set +a

# Validate required vars
for var in SMB_SERVER SMB_SHARE SMB_USERNAME SMB_PASSWORD MEDIA_PATH; do
  if [[ -z "${!var:-}" ]]; then
    fail "$var is not set in .env"
  fi
done

MOUNT_POINT="$MEDIA_PATH"

is_mounted() {
  mount | grep -q "$MOUNT_POINT" 2>/dev/null
}

do_mount() {
  # Create mount point if it doesn't exist
  if [[ ! -d "$MOUNT_POINT" ]]; then
    info "Creating mount point: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
  fi

  if is_mounted; then
    ok "Share is already mounted at $MOUNT_POINT"
    return 0
  fi

  info "Mounting //${SMB_SERVER}/${SMB_SHARE} → $MOUNT_POINT ..."

  # Check if the server is reachable first
  if ! ping -c 1 -W 2 "$SMB_SERVER" &>/dev/null; then
    fail "Cannot reach Windows laptop at $SMB_SERVER\n  Make sure it's on and connected to the same network."
  fi

  # Mount using macOS smbfs
  if mount -t smbfs "//${SMB_USERNAME}:${SMB_PASSWORD}@${SMB_SERVER}/${SMB_SHARE}" "$MOUNT_POINT"; then
    ok "Mounted successfully at $MOUNT_POINT"
  else
    fail "Mount failed.\n  Check your SMB_USERNAME, SMB_PASSWORD, and SMB_SHARE values in .env\n  Also verify the folder is shared on the Windows laptop."
  fi

  # Create expected media subdirectories if they don't exist
  for dir in movies tv audiobooks podcasts; do
    if [[ ! -d "$MOUNT_POINT/$dir" ]]; then
      mkdir -p "$MOUNT_POINT/$dir"
      info "Created media folder: $MOUNT_POINT/$dir"
    fi
  done
}

do_unmount() {
  if ! is_mounted; then
    warn "Share is not currently mounted"
    return 0
  fi
  info "Unmounting $MOUNT_POINT ..."
  umount "$MOUNT_POINT"
  ok "Unmounted"
}

do_status() {
  if is_mounted; then
    ok "Share is mounted at $MOUNT_POINT"
    echo ""
    echo "Contents:"
    ls "$MOUNT_POINT" 2>/dev/null || warn "Mount point is empty or inaccessible"
  else
    warn "Share is NOT mounted"
    echo "  Run: ./scripts/mount-network-share.sh mount"
  fi
}

# ---- Main ----
ACTION="${1:-mount}"

case "$ACTION" in
  mount)    do_mount ;;
  unmount)  do_unmount ;;
  status)   do_status ;;
  *)
    echo "Usage: $0 {mount|unmount|status}"
    exit 1
    ;;
esac
