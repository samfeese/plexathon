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
```

## Hardware Setup

- **Mac mini**: Docker host running all services
- **Windows laptop**: SMB file share hosting media files
- **Network**: Both devices on same local network

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

## Network Share Strategy

### Why SMB Mount vs Running on Windows

The Windows laptop serves media files via SMB share, which the Mac mini mounts and accesses. We could run Docker containers directly on Windows, but this approach has advantages:

**Advantages of Mac mini as Docker host:**
- Always-on server (Mac mini is better suited for 24/7 operation)
- Lower power consumption than laptop
- Dedicated hardware for services
- Windows laptop can sleep/restart without affecting services

**SMB Mount approach:**
- Mac mini mounts Windows share: `/Volumes/Media`
- Docker containers access mounted path
- Windows laptop just needs to share folder, no Docker setup required
- Easier for non-technical person to manage (just keep share enabled)

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
└── scripts/
    ├── mount-network-share.sh    # SMB mount automation
    └── setup-cloudflare-tunnel.sh # Cloudflare tunnel setup wizard
```

## Environment Variables (.env)

```bash
# Timezone
TIMEZONE=America/New_York

# Media storage path (where SMB share is mounted)
MEDIA_PATH=/Volumes/Media

# Network share settings (Windows laptop)
SMB_SERVER=192.168.1.100          # Windows laptop IP
SMB_SHARE=Media                   # Share name
SMB_USERNAME=username             # Windows user
SMB_PASSWORD=password             # Windows password

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
- Checks for Docker Desktop
- Creates `.env` from template (prompts for editing)
- Mounts SMB share from Windows laptop
- Creates all necessary directories and service configs
- Starts Docker containers (skips cloudflared if not yet configured)
- Displays access URLs

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

## Network Share Auto-Mounting

**Challenge:** Docker containers need the SMB share mounted before they start.

**Solution:** LaunchAgent runs `mount-network-share.sh` on boot.

**LaunchAgent location:**
`~/Library/LaunchAgents/com.homelab.mount.plist`

**Mount script:**
- Checks if share is already mounted
- Mounts using credentials from `.env`
- Creates media subdirectories if missing

**Manual remount:**
```bash
./scripts/mount-network-share.sh mount
```

## Media Directory Structure

Expected layout on Windows share:

```
/Volumes/Media/  (or wherever SMB share is mounted)
├── audiobooks/
│   ├── Author Name/
│   │   └── Book Title/
│   │       ├── chapter01.mp3
│   │       ├── chapter02.mp3
│   │       └── cover.jpg
├── podcasts/
│   └── Podcast Name/
│       └── episodes/
├── movies/
│   └── Movie Name (Year)/
│       └── Movie Name (Year).mkv
└── tv/
    └── Show Name/
        └── Season 01/
            └── Show - S01E01.mkv
```

## Platform Differences: macOS vs Linux

This repo was originally designed for macOS (Mac mini). For Linux (Ubuntu/WSL), adjust:

### Path Differences

**macOS:**
- User directory: `/Users/username`
- Homebrew: `/usr/local/bin` or `/opt/homebrew/bin` (Apple Silicon)
- LaunchAgents: `~/Library/LaunchAgents/`

**Linux:**
- User directory: `/home/username`
- Package manager: `apt` instead of `brew`
- Systemd services: `/etc/systemd/system/` instead of LaunchAgents

### SMB Mounting

**macOS:**
```bash
mount -t smbfs "//user:pass@server/share" /Volumes/ShareName
```

**Linux:**
```bash
# Install cifs-utils first
sudo apt install cifs-utils

# Mount
sudo mount -t cifs //server/share /mnt/ShareName -o username=user,password=pass
```

**Persistent mount (Linux /etc/fstab):**
```
//server/share /mnt/ShareName cifs credentials=/home/user/.smbcredentials,uid=1000,gid=1000 0 0
```

Where `.smbcredentials`:
```
username=user
password=pass
```

### Auto-start Services

**macOS:** LaunchAgents (XML plist files)
**Linux:** Systemd service units

**Example systemd service for mount:**
```ini
# /etc/systemd/system/mount-media.service
[Unit]
Description=Mount SMB Media Share
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/home/user/homelab/scripts/mount-network-share.sh mount
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable: `sudo systemctl enable mount-media.service`

### Docker Installation

**macOS:** Docker Desktop (GUI application)
**Linux:** Docker Engine (daemon)

```bash
# Linux install
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

## Security Considerations

### Credentials Storage

- `.env` file contains plaintext passwords
- **Never commit `.env` to git** (in `.gitignore`)
- SMB credentials stored in `mount-network-share.sh` and LaunchAgent
- Cloudflare tunnel credentials in `cloudflared/<tunnel-id>.json`

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

### SMB share not mounting

```bash
# Check if share is accessible
smbutil view //SMB_SERVER

# Try manual mount
mount -t smbfs "//user:pass@server/share" /Volumes/ShareName

# Check mount status
mount | grep ShareName

# Remount via script
./scripts/mount-network-share.sh mount
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

- **Sonarr/Radarr**: Automated TV/movie downloading and management
- **Prowlarr**: Indexer management for Sonarr/Radarr
- **Transmission/qBittorrent**: Torrent client
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
