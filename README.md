# Plexathon 🎬

Your personal media server — Plex, audiobooks, torrents, and more, running on your Mac mini.

---

## What This Does

Turns your Mac mini into a home media server that you can access from anywhere:

| Service | What It's For |
|---|---|
| **Plex** | Watch movies and TV shows |
| **Audiobookshelf** | Listen to audiobooks and podcasts |
| **qBittorrent** | Download torrents — all traffic routed through ProtonVPN |
| **FileBrowser** | Browse and manage your media files from a browser |
| **Homepage** | A simple dashboard with links to everything |
| **Cloudflare Tunnel** | Secure remote access — no router config needed |

Your media files live on an external drive plugged into the Mac mini.

---

## Before You Start

You'll need:

- [ ] **Mac mini** plugged in and on (this is where everything runs)
- [ ] **External hard drive** plugged into the Mac mini (for storing all your media)
- [ ] **Docker Desktop** installed on the Mac mini → [Download here](https://www.docker.com/products/docker-desktop/)
- [ ] A **free Plex account** → [Sign up here](https://www.plex.tv/sign-up/)
- [ ] A **ProtonVPN account** (for safe torrenting) → [Sign up here](https://proton.me/vpn)
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
- `MEDIA_PATH` — the path to your external drive (plug it in, find its name in Finder under "Locations", it'll be `/Volumes/<name>`)
- `PLEX_CLAIM` — your Plex claim token from [plex.tv/claim](https://www.plex.tv/claim/) — get it right before running setup, it expires in 4 minutes
- `PROTONVPN_PRIVATE_KEY` — your WireGuard key from ProtonVPN (see below)

**Getting your ProtonVPN WireGuard key:**
1. Log in at proton.me → VPN → Downloads → WireGuard configuration
2. Click Create, choose any server
3. Copy the `PrivateKey` value from the `[Interface]` section

### Step 3 — Allow Docker to access your drive

1. Open **Docker Desktop**
2. Go to **Settings → Resources → File Sharing**
3. Add the path to your external drive (e.g. `/Volumes/MediaDrive`)
4. Click **Apply & Restart**

### Step 4 — Run setup

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
| qBittorrent | http://localhost:8090 |
| FileBrowser | http://localhost:8080 |
| Dashboard | http://localhost:3000 |

**From anywhere** (after Cloudflare tunnel setup):

| Service | Address |
|---|---|
| Plex | https://plex.yourdomain.com |
| Audiobookshelf | https://audiobooks.yourdomain.com |
| qBittorrent | https://torrents.yourdomain.com |
| FileBrowser | https://files.yourdomain.com |
| Dashboard | https://home.yourdomain.com |

---

## Downloading & Adding Media

1. Open qBittorrent at `localhost:8090`
2. Add a torrent (paste a magnet link or upload a .torrent file)
3. Downloads go to the `downloads/` folder on your drive
4. Move completed files into `movies/` or `tv/` and Plex will pick them up on the next scan

**Tip:** Install the [Torrent Control](https://github.com/Douman/torrent-control) browser extension to send magnet links directly to qBittorrent with one click.

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

**qBittorrent won't start / VPN not connecting:**
- Check logs: `docker-compose logs -f gluetun`
- Make sure `PROTONVPN_PRIVATE_KEY` is set correctly in `.env`
- Try a different country in `PROTONVPN_COUNTRY`

**Plex isn't showing my media:**
1. Make sure the external drive is plugged in
2. Check it's showing up in Finder under "Locations"
3. Verify Docker has file sharing access: Docker Desktop → Settings → Resources → File Sharing

**Cloudflare tunnel not connecting:**
- Check it's running: `docker-compose logs -f cloudflared`
- Make sure `cloudflared/config.yml` exists (run `./scripts/setup-cloudflare-tunnel.sh` if not)
- Verify DNS records in your Cloudflare dashboard have Proxy ON (orange cloud)

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

Files on the external drive:

```
MediaDrive/
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
├── podcasts/
└── downloads/        ← torrents land here, move to above folders when done
```
