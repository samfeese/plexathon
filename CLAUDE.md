# Homelab Docker Stack - Setup Guide

## Project Overview

Self-hosted media server and file management stack designed to run on a Mac mini, pulling media from a Windows laptop network share, with secure remote access via Cloudflare Tunnel.

## Architecture

```
Internet
  ↓
Cloudflare (SSL termination + routing by hostname)
  ↓
cloudflared container (tunnel, ingress rules in config.yml)
  ↓
Docker Containers:
  - Plex (movies & TV)          ← plex.yourdomain.com
  - Audiobookshelf (audiobooks) ← audiobooks.yourdomain.com
  - FileBrowser (file manager)  ← files.yourdomain.com
  - Homepage (dashboard)        ← home.yourdomain.com
  - qBittorrent (via gluetun)   ← torrents.yourdomain.com
  - Gluetun (ProtonVPN)         ← no direct access, network layer only
```

## Hardware Setup

- **Mac mini**: Docker host running all services
- **External drive**: Plugged directly into the Mac mini, holds all media and downloads
- **Network**: Mac mini connected to router (wired preferred)

## Services

### Core Services

1. **Cloudflare Tunnel** (cloudflared container)
   - Ingress rules in `cloudflared/config.yml` map each hostname to a container
   - SSL handled entirely by Cloudflare — no cert management needed
   - No open ports on the Mac mini or router
   - Replaces the need for a reverse proxy like Nginx

2. **Audiobookshelf** (port 13378)
   - Purpose-built audiobook and podcast server
   - Progress tracking, mobile apps, metadata fetching
   - Superior to Plex for audiobook management

3. **Plex** (port 32400)
   - Industry-standard media server for movies/TV
   - Rich client apps across all platforms
   - Hardware transcoding support (Plex Pass required)

4. **FileBrowser** (port 8080)
   - Web-based file manager
   - Upload/download files via browser
   - User management and permissions

5. **Homepage** (port 3000)
   - Dashboard linking all services
   - Service status monitoring
   - Quick access to all apps

6. **Gluetun** (no direct port — network container)
   - ProtonVPN client using WireGuard protocol
   - Built-in kill switch: if VPN drops, torrent traffic stops rather than leaking
   - qBittorrent runs inside this container's network namespace via `network_mode: service:gluetun`

7. **qBittorrent** (port 8090, published on gluetun)
   - Torrent client with web UI
   - All traffic routed through ProtonVPN automatically
   - Downloads land in `${MEDIA_PATH}/downloads`
   - Port published on gluetun container, not directly on qbittorrent

## Media Storage

All media lives on an external drive plugged directly into the Mac mini, mounted at `/Volumes/<drive-name>` (set via `MEDIA_PATH` in `.env`).

**Drive layout:**
```
/Volumes/MediaDrive/
├── movies/       ← Plex movies library
├── tv/           ← Plex TV library
├── audiobooks/   ← Audiobookshelf library
├── podcasts/     ← Audiobookshelf podcasts
└── downloads/    ← qBittorrent download destination
```

**Docker Desktop File Sharing:** macOS requires explicitly allowing Docker to access volumes outside the home directory. In Docker Desktop → Settings → Resources → File Sharing, add the drive path (e.g. `/Volumes/MediaDrive`).

## Remote Access Strategy

### Cloudflare Tunnel vs Traditional Port Forwarding

**Cloudflare Tunnel (recommended):**
- Creates outbound tunnel FROM Mac mini TO Cloudflare
- No router configuration needed
- No ports exposed on home network
- Works behind restrictive ISPs/CGNAT
- Free tier sufficient for personal use
- Built-in DDoS protection

**How it works:**
1. `cloudflared` container runs on Mac mini
2. Establishes persistent connection to Cloudflare
3. `cloudflared/config.yml` defines ingress rules: each hostname → internal container
4. Cloudflare DNS points subdomains to the tunnel (`<tunnel-id>.cfargotunnel.com`)
5. Traffic routes: Internet → Cloudflare (SSL) → Tunnel → Container directly

No reverse proxy layer needed — Cloudflare's ingress rules handle all routing.

**Alternative: Traditional Port Forwarding**
- Requires opening ports 80/443 on router
- Exposes home IP address
- Doesn't work behind CGNAT
- Security depends on proper configuration
- We're avoiding this approach

## File Structure

```
homelab-stack/
├── .env                          # Environment configuration (not in git)
├── .env.example                  # Template for .env
├── docker-compose.yml            # All service definitions
├── setup.sh                      # Main setup script
├── README.md                     # User documentation
├── CLAUDE.md                     # This file - developer context
├── cloudflared/
│   ├── config.yml.example        # Cloudflare tunnel config template
│   └── <tunnel-id>.json          # Tunnel credentials (created during setup)
├── audiobookshelf/
│   ├── config/                   # App configuration
│   └── metadata/                 # Audiobook metadata cache
├── plex/
│   ├── config/                   # Plex configuration and metadata
│   └── transcode/                # Transcoding temp files
├── filebrowser/
│   ├── database.db               # FileBrowser database
│   └── config.json               # FileBrowser settings
├── homepage/
│   ├── services.yaml             # Dashboard service definitions
│   └── settings.yaml             # Dashboard settings
├── gluetun/                      # Gluetun state (created at runtime)
├── qbittorrent/
│   └── config/                   # qBittorrent configuration
└── scripts/
    └── setup-cloudflare-tunnel.sh # Cloudflare tunnel setup wizard
```

## Environment Variables (.env)

```bash
# Timezone
TIMEZONE=America/New_York

# Media storage path (where SMB share is mounted)
MEDIA_PATH=/Volumes/MediaDrive     # Path to external drive

# Domain for external access
DOMAIN=yourdomain.com
```

## Setup Workflow

### 1. Initial Setup (Mac mini)

```bash
# Clone repo
git clone <repo-url> homelab
cd homelab

# Run setup script
./setup.sh
```

**Setup script does:**
- Checks for Docker Desktop is installed and running
- Creates `.env` from template (prompts for editing)
- Verifies external drive is accessible at `MEDIA_PATH`
- Checks Docker has file sharing permission for the drive path
- Creates media subdirectories on the drive (`movies/`, `tv/`, `downloads/`, etc.)
- Generates service configs (FileBrowser, Homepage)
- Starts Docker containers (skips cloudflared if not yet configured)
- Displays access URLs and first-time steps

### 2. Configure Services

**Audiobookshelf (http://localhost:13378):**
- Create admin account
- Add library pointing to `/audiobooks`
- Scan for audiobooks

**Plex (http://localhost:32400/web):**
- Sign in with Plex account (required)
- Run setup wizard
- Add libraries:
  - Movies: `/media/movies`
  - TV Shows: `/media/tv`

**FileBrowser (http://localhost:8080):**
- Default login: `admin` / `admin`
- Change password
- Manages files in `/srv` (mapped to entire media share)

### 3. Cloudflare Tunnel Setup (Remote Access)

```bash
./scripts/setup-cloudflare-tunnel.sh
```

**This script:**
1. Installs `cloudflared` (via Homebrew)
2. Authenticates with Cloudflare account
3. Creates tunnel and saves credentials to `./cloudflared/`
4. Generates `cloudflared/config.yml` with per-hostname ingress rules
5. Prints DNS records to add in Cloudflare dashboard
6. Starts all services including the tunnel

**Ingress config pattern** (`cloudflared/config.yml`):
```yaml
ingress:
  - hostname: plex.yourdomain.com
    service: http://localhost:32400      # host network (Plex)
  - hostname: audiobooks.yourdomain.com
    service: http://audiobookshelf:80   # container name routing
  - hostname: files.yourdomain.com
    service: http://filebrowser:80
  - hostname: home.yourdomain.com
    service: http://homepage:3000
  - service: http_status:404            # required catch-all
```

**DNS records to add** (Cloudflare dashboard → your domain → DNS):
- Each subdomain: `CNAME` → `<tunnel-id>.cfargotunnel.com`, Proxy ON

No reverse proxy needed — Cloudflare handles SSL and routing directly.

## Media Directory Structure

Expected layout on the external drive:

```
/Volumes/MediaDrive/
├── movies/
│   └── Movie Name (Year)/
│       └── Movie Name (Year).mkv
├── tv/
│   └── Show Name/
│       └── Season 01/
│           └── Show Name - S01E01.mkv
├── audiobooks/
│   └── Author Name/
│       └── Book Title/
│           ├── 01 - Chapter.mp3
│           └── cover.jpg
├── podcasts/
│   └── Podcast Name/
│       └── episodes/
└── downloads/        ← qBittorrent drops files here
```

Completed downloads from qBittorrent land in `downloads/`. Move or copy them into `movies/` or `tv/` and trigger a Plex library scan.

## Security Considerations

### Credentials Storage

- `.env` file contains plaintext passwords and VPN keys
- **Never commit `.env` to git** (in `.gitignore`)
- Cloudflare tunnel credentials in `cloudflared/<tunnel-id>.json` (also gitignored)

### Network Security

**What's exposed locally:**
- All services on `localhost` (127.0.0.1)
- Accessible from any device on local network via Mac mini IP

**What's exposed externally:**
- Only subdomains defined in `cloudflared/config.yml` ingress rules
- SSL/TLS handled entirely by Cloudflare
- Protected by Cloudflare's infrastructure

**Best practices:**
- Use strong passwords for all services
- Enable 2FA where available (Audiobookshelf, Plex support this)
- Regularly update containers: `docker-compose pull && docker-compose up -d`
- Monitor cloudflared logs periodically
- Use Cloudflare's WAF rules if needed (Cloudflare dashboard)

## Troubleshooting

### External drive not accessible

```bash
# Check if drive is mounted
ls /Volumes/

# Check Docker has file sharing permission
# Docker Desktop → Settings → Resources → File Sharing
# Add the drive path if missing, click Apply & Restart
```

### Container won't start

```bash
# Check container logs
docker-compose logs -f <service-name>

# Check if port is already in use
lsof -i :PORT_NUMBER

# Restart specific service
docker-compose restart <service-name>

# Rebuild and restart
docker-compose up -d --force-recreate <service-name>
```

### Cloudflare Tunnel not working

```bash
# Check cloudflared logs
docker-compose logs -f cloudflared

# Verify DNS records in Cloudflare dashboard
# Ensure CNAME points to: <tunnel-id>.cfargotunnel.com

# Test tunnel connectivity
cloudflared tunnel info <tunnel-name>

# Restart tunnel
docker-compose restart cloudflared
```

### Can't access services remotely

1. Verify tunnel is running: `docker ps | grep cloudflared`
2. Check cloudflared logs: `docker-compose logs -f cloudflared`
3. Check DNS propagation: `nslookup plex.yourdomain.com` (should resolve to Cloudflare IPs)
4. Verify `cloudflared/config.yml` has the correct hostname and service entries
5. Confirm DNS records in Cloudflare dashboard have Proxy ON (orange cloud)

### Performance issues

**Transcoding lag (Plex):**
- Enable hardware transcoding in Plex settings (requires Plex Pass)
- Reduce transcoding quality or allow direct play
- Pre-transcode large files

**Network share slow:**
- Check Windows laptop isn't sleeping
- Verify SMB version (SMB3 is faster than SMB1)
- Consider wired connection instead of WiFi
- Monitor network bandwidth

## Management Commands

```bash
# View all running containers
docker-compose ps

# View logs for all services
docker-compose logs -f

# View logs for specific service
docker-compose logs -f audiobookshelf

# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart plex

# Stop all services
docker-compose down

# Stop and remove all data (nuclear option)
docker-compose down -v

# Update all container images
docker-compose pull
docker-compose up -d

# Rebuild specific service
docker-compose up -d --force-recreate --build plex
```

## Future Enhancements

Potential additions to the stack:

- **Sonarr/Radarr**: Automated TV/movie downloading and management (pairs with qBittorrent)
- **Prowlarr**: Indexer management for Sonarr/Radarr
- **Tautulli**: Plex monitoring and statistics
- **Organizr**: Unified dashboard (alternative to Homepage)
- **Duplicati**: Automated backups
- **Watchtower**: Automatic container updates
- **Portainer**: Docker container management GUI
- **Calibre-Web**: Ebook library management
- **Nextcloud**: Personal cloud storage
- **Paperless-ngx**: Document management system

## Development Notes

### Adding New Services

1. Add service to `docker-compose.yml`:
```yaml
  new-service:
    image: org/image:latest
    container_name: new-service
    restart: unless-stopped
    ports:
      - "PORT:PORT"
    volumes:
      - ./new-service:/config
    environment:
      - TZ=${TIMEZONE}
```

2. Create directory: `mkdir -p new-service`

3. Update `setup.sh` to create any necessary configs

4. Add to Homepage dashboard in `homepage/services.yaml`

5. Add proxy host in Nginx Proxy Manager if external access needed

### Testing Changes

```bash
# Validate docker-compose syntax
docker-compose config

# Dry-run to see what would happen
docker-compose up --no-start

# Start in foreground to see logs
docker-compose up

# Once working, detach
docker-compose up -d
```

## Requirements

### Hardware
- Mac mini (or any macOS/Linux machine)
- Windows laptop (or any SMB-capable file server)
- Both on same network

### Software
- macOS 10.15+ or Linux (Ubuntu 20.04+)
- Docker Desktop (macOS) or Docker Engine (Linux)
- Git
- Web browser

### External Services
- Domain name (can use Cloudflare Registrar, Namecheap, etc.)
- Cloudflare account (free tier sufficient)

### Network
- Router with internet access
- Local network connectivity between devices
- (Optional) Static IP for Mac mini on local network

## License

MIT or appropriate license for homelab projects

## Credits

Built for easy self-hosting of media services with secure remote access. Designed for users who want the convenience of cloud services with the control of self-hosting.
