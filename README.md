# VPN-Protected Media Stack

GitOps-ready media downloading stack with VPN protection (Mullvad/Spain) and automatic Polish subtitles.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GLUETUN (VPN)                            │
│               Spanish Exit IP: 193.x.x.x                    │
│  ┌───────────┐ ┌─────────┐ ┌────────┐ ┌────────┐          │
│  │qBittorrent│ │Prowlarr │ │ Sonarr │ │ Radarr │          │
│  │  :8080    │ │  :9696  │ │ :8989  │ │ :7878  │          │
│  └───────────┘ └─────────┘ └────────┘ └────────┘          │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ~/Media/tv      ~/Media/movies     Bazarr (:6767)
              │               │           (Polish subs)
              └───────┬───────┘
                      ▼
               Jellyfin (:8096)
```

## Quick Start

```bash
# 1. Configure
cp .env.example .env
nano .env  # Add Mullvad credentials

# 2. Run init script (does everything)
chmod +x init.sh
./init.sh

# 3. Done! Add series in Sonarr
open http://localhost:8989
```

## What's Pre-configured

| Service | Configuration |
|---------|--------------|
| **qBittorrent** | Seeding disabled (ratio=0), bound to VPN interface |
| **Prowlarr** | 1337x, TorrentGalaxy, EZTV indexers |
| **Sonarr** | Connected to qBittorrent, root folder `/tv` |
| **Radarr** | Connected to qBittorrent, root folder `/movies` |
| **Bazarr** | Polish language, OpenSubtitles + Napisy24 providers |

## Directory Structure

```
arr-stack/
├── docker-compose.yml      # Service definitions
├── .env.example            # Configuration template
├── .env                    # Your secrets (gitignored)
├── init.sh                 # One-time setup script
├── config/
│   ├── qbittorrent/        # qBittorrent config
│   ├── prowlarr/           # Prowlarr config
│   ├── sonarr/             # Sonarr config
│   ├── radarr/             # Radarr config
│   ├── bazarr/             # Bazarr config (Polish subs)
│   ├── jellyfin/           # Jellyfin config
│   └── gluetun/            # VPN config
└── README.md
```

## Services

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| qBittorrent | http://localhost:8080 | admin / adminadmin |
| Prowlarr | http://localhost:9696 | - |
| Sonarr | http://localhost:8989 | - |
| Radarr | http://localhost:7878 | - |
| Bazarr | http://localhost:6767 | - |
| Jellyfin | http://localhost:8096 | Setup wizard |

## Usage

### Download a TV Series

1. Open Sonarr: http://localhost:8989
2. Series → Add New
3. Search for series name
4. Select quality profile (HD-1080p recommended)
5. Click Add → Search All
6. Bazarr auto-downloads Polish subtitles

### Check VPN Status

```bash
# Verify Spanish exit IP
docker exec gluetun wget -qO- ifconfig.me
```

### View Logs

```bash
docker-compose logs -f gluetun
docker-compose logs -f sonarr
```

### Stop/Start

```bash
docker-compose down
docker-compose up -d
```

## Configuration Changes

All config files are in `./config/`. Changes persist across restarts.

To commit config changes to git:

```bash
# Configs are tracked, secrets are not
git add config/
git commit -m "Update configuration"
```

## Mullvad Setup

1. Create account: https://mullvad.net (no email required)
2. Go to: Account → WireGuard configuration
3. Generate key
4. Copy to `.env`:
   - `MULLVAD_PRIVATE_KEY=<your key>`
   - `MULLVAD_ADDRESS=<your address>`

## Polish Subtitles (Bazarr)

Pre-configured providers:
- **OpenSubtitles.com** - Needs free account
- **Napisy24** - Works without account
- **Subscene** - Backup
- **Podnapisi** - Backup

To add OpenSubtitles credentials:
1. Create account: https://opensubtitles.com
2. Open Bazarr: http://localhost:6767
3. Settings → Providers → OpenSubtitles.com
4. Add username/password

## macOS Notes

**Docker Desktop Required:** Install from https://docker.com/products/docker-desktop

**TUN Device:** Gluetun needs `/dev/net/tun`. Usually works with Docker Desktop's virtualization framework.

**File Sharing:** Ensure Docker Desktop has access to your Media folder (Settings → Resources → File Sharing).

## Security Notes

- ✅ All torrent traffic routes through VPN
- ✅ Kill switch enabled (no VPN = no connection)
- ✅ Seeding disabled by default
- ✅ qBittorrent bound to tun0 interface
- ✅ Secrets in `.env` (gitignored)

## Troubleshooting

### VPN won't connect
```bash
docker logs gluetun
# Check Mullvad credentials in .env
```

### Services can't reach each other
```bash
# They share gluetun's network, use localhost
docker exec sonarr curl -s http://localhost:8080
```

### Permission errors
```bash
# Check your PUID/PGID in .env
id -u  # Should match PUID
id -g  # Should match PGID
```

### Subtitles not downloading
1. Check Bazarr providers are enabled
2. Some new shows take days for subs to appear
3. Try manual search in Bazarr
