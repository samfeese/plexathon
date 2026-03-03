# Plexathon 🎬

Your personal media server — Plex, audiobooks, and more, running on your Mac mini.

---

## What This Does

Turns your Mac mini into a home media server that you can access from anywhere:

| Service | What It's For |
|---|---|
| **Plex** | Watch movies and TV shows |
| **Audiobookshelf** | Listen to audiobooks and podcasts |
| **FileBrowser** | Browse and manage your media files from a browser |
| **Homepage** | A simple dashboard with links to everything |
| **qBittorrent** | Torrent client — all traffic routed through ProtonVPN |
| **Cloudflare Tunnel** | Secure remote access — no router config needed |

Your media files live on the Windows laptop and are shared over your home network. The Mac mini reads them and serves them up through Plex.

---

## Before You Start

You'll need:

- [ ] **Mac mini** plugged in and on (this is where everything runs)
- [ ] **Windows laptop** on the same WiFi/network with a shared folder set up
- [ ] **Docker Desktop** installed on the Mac mini → [Download here](https://www.docker.com/products/docker-desktop/)
- [ ] A **free Plex account** → [Sign up here](https://www.plex.tv/sign-up/)
- [ ] About **30 minutes**

---

## Setup (One Time)

### Step 1 — Download this project

Open **Terminal** on the Mac mini and run:

```bash
git clone https://github.com/YOUR_USERNAME/plexathon.git
cd plexathon
```

### Step 2 — Configure your settings

```bash
cp .env.example .env
open -e .env
```

This opens a text file. Fill in:
- Your Windows laptop's IP address
- Your Windows username and password
- Your Plex claim token (get one at [plex.tv/claim](https://www.plex.tv/claim/) — it expires in 4 minutes so do this right before running setup)

### Step 3 — Run setup

```bash
./setup.sh
```

The script will walk you through the rest. When it's done, it'll show you the addresses for each service.

---

## Daily Use

Everything runs automatically in the background. You don't need to do anything.

**Access your services** (while on home network):

| Service | Address |
|---|---|
| Plex | http://localhost:32400/web |
| Audiobookshelf | http://localhost:13378 |
| FileBrowser | http://localhost:8080 |
| Dashboard | http://localhost:3000 |

**From anywhere** (after Cloudflare tunnel setup):

| Service | Address |
|---|---|
| Plex | https://plex.yourdomain.com |
| Audiobookshelf | https://audiobooks.yourdomain.com |
| FileBrowser | https://files.yourdomain.com |
| Dashboard | https://home.yourdomain.com |
| qBittorrent | https://torrents.yourdomain.com |

---

## Managing Services

```bash
# Check everything is running
docker-compose ps

# Restart everything
docker-compose restart

# Restart just Plex
docker-compose restart plex

# View logs if something looks wrong
docker-compose logs -f plex

# Update to latest versions
docker-compose pull && docker-compose up -d
```

---

## If Something's Not Working

**Cloudflare tunnel not connecting:**
- Check it's running: `docker-compose logs -f cloudflared`
- Make sure `cloudflared/config.yml` exists (run `./scripts/setup-cloudflare-tunnel.sh` if not)
- Verify DNS records in your Cloudflare dashboard have Proxy ON (orange cloud)

**Plex isn't showing my media:**
1. Make sure the Windows laptop is on and not sleeping
2. Check the shared folder is still shared in Windows settings
3. Run `./scripts/mount-network-share.sh mount` to remount

**Can't access from outside home:**
- Make sure the Cloudflare tunnel is running: `docker-compose logs -f cloudflared`
- Check your domain's DNS records in the Cloudflare dashboard (Proxy must be ON)

**Something else:**
- Check logs: `docker-compose logs -f`
- Restart everything: `docker-compose restart`

---

## Setting Up Remote Access

To access your media from outside your home network, run:

```bash
./scripts/setup-cloudflare-tunnel.sh
```

You'll need:
- A domain name (~$10/year from [Cloudflare Registrar](https://www.cloudflare.com/products/registrar/) or Namecheap)
- A free [Cloudflare account](https://www.cloudflare.com/)

The script walks you through everything — it creates the tunnel, generates the config, and tells you exactly which DNS records to add. Cloudflare handles SSL automatically, no certificates to manage.

---

## Your Media Folder Layout

Put your files on the Windows laptop like this:

```
Media/                        ← the shared folder
├── movies/
│   └── The Matrix (1999)/
│       └── The Matrix (1999).mkv
├── tv/
│   └── Breaking Bad/
│       └── Season 01/
│           └── Breaking Bad - S01E01.mkv
├── audiobooks/
│   └── Author Name/
│       └── Book Title/
│           ├── 01 - Chapter.mp3
│           └── cover.jpg
└── podcasts/
```
