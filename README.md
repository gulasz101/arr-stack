# 🏴‍☠️ Arr Stack — Homelab Media Server

A complete self-hosted media server stack running on a dedicated homelab mini PC, with media storage on a NAS, VPN kill-switch, automatic downloads, and Polish subtitle support.

**The problem it solves:** The family wants to watch media on the TV without the laptop needing to be on. The stack runs 24/7 on a dedicated box, accessible from the local network and remotely over NetBird VPN.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         MacBook (dev)                           │
│   git push ──────────────────────────► GitHub (private repo)   │
└─────────────────────────────────────────────────────────────────┘
                                              │
                                    git pull + just deploy
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  arr-box.local (Debian 13 mini PC)              │
│                  arr-box.netbird.cloud (NetBird VPN)            │
│                  192.168.1.162                                   │
│                                                                 │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │
│  │  Caddy  │  │ Homepage │  │ Jellyfin │  │    Bazarr      │  │
│  │ (proxy) │  │(dashboard│  │  (media) │  │  (subtitles)   │  │
│  └────┬────┘  └──────────┘  └──────────┘  └────────────────┘  │
│       │                                                         │
│  ┌────▼──────────────────────────────────────┐                 │
│  │           Gluetun (Mullvad VPN)           │                 │
│  │   ┌─────────┐ ┌────────┐ ┌──────────────┐│                 │
│  │   │ Sonarr  │ │ Radarr │ │   Prowlarr   ││                 │
│  │   │  (TV)   │ │(movies)│ │  (indexers)  ││                 │
│  │   └─────────┘ └────────┘ └──────────────┘│                 │
│  │   ┌─────────────┐  ┌──────────────────┐  │                 │
│  │   │qBittorrent  │  │   FlareSolverr   │  │                 │
│  │   │ (torrents)  │  │ (Cloudflare fix) │  │                 │
│  │   └─────────────┘  └──────────────────┘  │                 │
│  └─────────────────────────────────────────-┘                 │
│                    ║ VPN Kill Switch ║                          │
└──────────────────────────┬──────────────────────────────────────┘
                           │ NFS
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              openmediavault.local (NAS)                         │
│              192.168.1.180                                       │
│                                                                 │
│  /mnt/media     (3.7T)  ── TV shows, movies                    │
│  /mnt/downloads (1.4T)  ── qBittorrent downloads               │
│  Copyparty      :3923   ── file upload endpoint (LAN, no auth) │
└─────────────────────────────────────────────────────────────────┘
```

Services behind Gluetun share its network namespace (`network_mode: service:gluetun`). If the VPN disconnects, the kill-switch fires and those services lose all network access — no IP leak possible.

---

## Access

| Client | URL |
|---|---|
| Browser (LAN) | `http://arr-box.local` |
| Browser (NetBird VPN) | `http://arr-box.netbird.cloud` |
| Direct IP | `http://192.168.1.162` |
| Jellyfin | `http://jellyfin.arr-box.local` |
| Sonarr | `http://sonarr.arr-box.local` |
| Radarr | `http://radarr.arr-box.local` |
| Prowlarr | `http://prowlarr.arr-box.local` |
| qBittorrent | `http://qbit.arr-box.local` |
| Bazarr | `http://bazarr.arr-box.local` |

All `.arr-box.local` subdomains also work as `.arr-box.netbird.cloud` over VPN.

> **Android TV:** Use `http://192.168.1.162:8096` directly for Jellyfin — mDNS subdomains are not reliable on Android clients.

> **DNS:** Subdomain resolution requires OPNsense host overrides or a DNS server that resolves `*.arr-box.local`. See [DNS Setup](#dns-setup) below.

---

## Services

| Service | Role | VPN | Port |
|---|---|---|---|
| Caddy | Reverse proxy | No | 80 |
| Homepage | Dashboard | No | 3000 |
| Jellyfin | Media streaming | No | 8096 |
| Sonarr | TV series automation | Yes (gluetun) | 8989 |
| Radarr | Movie automation | Yes (gluetun) | 7878 |
| Prowlarr | Indexer management | Yes (gluetun) | 9696 |
| qBittorrent | Torrent client | Yes (gluetun) | 8080 |
| Bazarr | Subtitle automation | No | 6767 |
| FlareSolverr | Cloudflare bypass | Yes (gluetun) | 8191 |
| Gluetun | Mullvad WireGuard VPN | — | — |

Authentication is disabled for all management services — the stack is LAN-trusted. Jellyfin has per-user accounts.

---

## Prerequisites

### Hardware
- **arr-box:** Any x86-64 mini PC running Debian 13 (tested: `arr-box.local` / `192.168.1.162`)
- **NAS:** OpenMediaVault with at least two disks (3.7T for media, 1.4T for downloads)

### Software (on MacBook/dev machine)
```bash
brew install age sops just
```

### Mullvad VPN
A [Mullvad](https://mullvad.net) account with a WireGuard key generated at `Account → WireGuard configuration`.

---

## Quick Start (deploying to arr-box)

### 1. Clone the repo

```bash
git clone git@github.com:gulasz101/arr-stack.git
cd arr-stack
```

### 2. Set up secrets

Secrets are encrypted with [age](https://age-encryption.org/) via [SOPS](https://github.com/getsops/sops). The encrypted `.env.sops` is committed to git; the plaintext `.env` is never committed.

**First time — generate an age key:**
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# Save the private key to 1Password: vault "Homelab", item "arr-stack age key"
```

**Install the age key on arr-box** (retrieve from 1Password):
```bash
ssh arr-box
sudo -u arrbox bash
mkdir -p ~/.config/sops/age
# paste private key content:
cat > ~/.config/sops/age/keys.txt
```

**Edit secrets:**
```bash
just secrets          # opens .env.sops in $EDITOR, re-encrypts on save
```

**Re-encrypt after editing `.env` directly:**
```bash
just encrypt
```

### 3. Deploy

```bash
# On arr-box:
cd /opt/arr-stack
just deploy           # decrypts .env.sops → .env, then docker compose up -d
```

Or from MacBook after committing:
```bash
git push
# On arr-box:
just pull-deploy
```

---

## justfile Commands

```
just deploy      — decrypt .env.sops → .env, then docker compose up -d
just update      — pull latest images + redeploy
just status      — docker compose ps
just logs        — live logs (all containers)
just log sonarr  — live logs for a specific service
just stop        — docker compose down
just decrypt     — decrypt .env.sops → .env only
just encrypt     — encrypt .env → .env.sops
just secrets     — edit .env.sops in-place (sops handles decrypt/re-encrypt)
just pull-deploy — git pull + deploy (run on arr-box)
just reset       — ⚠️ destroy all container config data
```

---

## Secrets Management

All secrets live in `.env.sops` — an age-encrypted dotenv file that is safe to commit to a private git repo.

```
.env.sops    ← encrypted, committed to git
.env         ← plaintext, git-ignored, generated by `just decrypt`
.sops.yaml   ← age public key config, committed to git
```

**SOPS requires `--input-type dotenv --output-type dotenv` flags** for dotenv format files. The justfile and systemd service handle this automatically.

The age private key lives in **1Password → vault "Homelab" → item "arr-stack age key"**. Without it, `.env.sops` cannot be decrypted.

---

## Autostart (Systemd)

The stack starts automatically on boot via `arr-stack.service`:

```bash
# Install (one-time, on arr-box):
sudo cp deploy/arr-stack.service /etc/systemd/system/
sudo cp deploy/arr-stack.service.d/env.conf /etc/systemd/system/arr-stack.service.d/
sudo systemctl daemon-reload
sudo systemctl enable arr-stack.service
```

The service:
1. Waits for `network-online.target` and `remote-fs.target` (NFS mounts)
2. Decrypts `.env.sops` → `.env` via sops
3. Runs `docker compose up -d`

A companion `wait-for-network.service` unit polls for the `192.168.1.0/24` route before signalling `network-online.target`, preventing NFS mount failures during DHCP race conditions at boot.

---

## DNS Setup

`*.arr-box.local` subdomains require a DNS resolver — mDNS only resolves exact hostnames.

### Option A: OPNsense host overrides (recommended for LAN)

**Services → Dnsmasq DNS & DHCP → Hosts** — add an entry for each subdomain pointing to `192.168.1.162`.

### Option B: dnsmasq on arr-box

Two dnsmasq instances run on arr-box (config in `deploy/`):

| Instance | Address | Purpose |
|---|---|---|
| `dnsmasq` (main) | `192.168.1.162:53` | LAN clients via OPNsense forwarding |
| `dnsmasq-netbird` | `100.96.191.232:5301` | NetBird peers via nameserver routing |

Both resolve:
- `*.arr-box.local` → `192.168.1.162`
- `*.arr-box.netbird.cloud` → `100.96.191.232`

**Deploy on arr-box:**
```bash
sudo cp deploy/dnsmasq-arr-stack.conf /etc/dnsmasq.d/arr-stack.conf
sudo cp deploy/dnsmasq-netbird.conf /etc/dnsmasq-netbird.conf
sudo cp deploy/dnsmasq-netbird.service /etc/systemd/system/
sudo systemctl restart dnsmasq
sudo systemctl enable --now dnsmasq-netbird
```

---

## NFS Storage

arr-box mounts media and downloads from OMV via NFS. The `arrbox` user (UID/GID 1100) owns all files on both machines.

**OMV exports** (`/etc/exports.d/arr-stack.exports`):
```
/srv/.../media     192.168.1.162(rw,sync,all_squash,anonuid=1100,anongid=1100)
/srv/.../downloads 192.168.1.162(rw,sync,all_squash,anonuid=1100,anongid=1100)
```

**arr-box fstab** (uses static IP — hostname causes mDNS race at boot):
```
192.168.1.180:/srv/.../media     /mnt/media      nfs  _netdev,nofail,soft,timeo=30,retry=3  0 0
192.168.1.180:/srv/.../downloads /mnt/downloads  nfs  _netdev,nofail,soft,timeo=30,retry=3  0 0
```

---

## File Transfer (Copyparty)

Copyparty runs permanently on OMV (port 3923) for parallel chunk HTTP uploads. This was used for the initial media migration (185G TV + 54G movies) and remains available for future transfers.

```bash
# Install on MacBook (pipx recommended on macOS):
pipx install copyparty

# Upload files to OMV:
u2c -q http://openmediavault.local:3923/tv /path/to/tv/
u2c -q http://openmediavault.local:3923/movies /path/to/movies/
```

---

## Directory Structure

```
arr-stack/
├── docker-compose.yml          # Stack definition
├── .env.sops                   # Encrypted secrets (committed)
├── .env                        # Plaintext secrets (git-ignored, runtime only)
├── .sops.yaml                  # age public key config
├── justfile                    # Task runner
├── config/
│   ├── caddy/
│   │   └── Caddyfile           # Reverse proxy routing
│   └── homepage/
│       ├── services.yaml       # Service links + widgets
│       ├── settings.yaml
│       └── widgets.yaml
├── deploy/
│   ├── arr-stack.service       # Systemd autostart unit
│   ├── arr-stack.service.d/
│   │   └── env.conf            # SOPS_AGE_KEY_FILE for systemd
│   ├── dnsmasq-arr-stack.conf  # dnsmasq LAN config
│   ├── dnsmasq-netbird.conf    # dnsmasq NetBird config
│   ├── dnsmasq-netbird.service # Systemd unit for second dnsmasq
│   └── wait-for-network.service# Boot race condition fix
└── docs/
    └── plans/
        ├── 2026-02-22-project-brief.md
        ├── 2026-02-22-homelab-migration-design.md
        └── 2026-02-22-homelab-migration-impl.md
```

---

## Troubleshooting

### VPN not connecting
```bash
docker logs gluetun | tail -20
docker exec gluetun wget -qO- https://ipinfo.io
# Should show Spain, not Germany
```

### NFS mounts not working after reboot
```bash
sudo systemctl status wait-for-network.service
sudo mount -a
df -h | grep mnt
```

### Caddy serving empty 200 after git pull
Git replaces file inodes — `caddy reload` isn't enough. Always restart:
```bash
docker restart caddy
```

### *arr service crashing on startup (InvalidCastException)
Don't use `AuthenticationMethod: None` — it's unsupported in Sonarr v4+. Use `External`:
```xml
<AuthenticationMethod>External</AuthenticationMethod>
<AuthenticationRequired>Enabled</AuthenticationRequired>
```

### Jellyfin not accessible on Android TV
Use direct IP+port, not subdomain:
```
http://192.168.1.162:8096
```
mDNS subdomain resolution is unreliable on Android clients.

### qBittorrent WebUI not loading
Check if the container is actually running (it shares gluetun's network — if gluetun is unhealthy, qBittorrent has no network):
```bash
docker ps | grep -E 'gluetun|qbit'
docker logs gluetun | tail -5
```

---

## 🇵🇱 Polish Subtitles

Bazarr is configured for Polish (`pl`) subtitles via:
- **Napisy24** — Polish-specific, no account needed
- **OpenSubtitles.com** — large database, free account required
- **NapiProjekt** — Polish, no account needed

---

Made with ❤️ and 🏴‍☠️ in Germany by a Polish pirate

*"Płynę przez morze torrentów, z polskimi napisami na pokładzie"* 🚢
