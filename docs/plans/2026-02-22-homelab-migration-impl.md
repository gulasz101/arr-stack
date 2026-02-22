# Arr-Stack Homelab Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Migrate the arr-stack (Jellyfin + *arr + qBittorrent) from a MacBook to a dedicated homelab (arr-box.local / arr-box.netbird.cloud), with media stored on OpenMediaVault NFS, secrets encrypted via SOPS+age in git, and systemd autostart.

**Architecture:** arr-box runs Docker Compose stack, mounting NFS shares from OMV (3.7T for media, 1.4T for downloads). Media migrated via Copyparty parallel chunk uploads. SOPS+age keeps secrets encrypted in the private GitHub repo; age key lives in 1Password.

**Tech Stack:** Docker Compose, Caddy, Gluetun/Mullvad, SOPS, age, just, NFS, Copyparty, Systemd, Debian 13, OpenMediaVault 6

---

## Environment Reference

| Item | Value |
|---|---|
| OMV hostname | `openmediavault.local` / `192.168.1.180` |
| OMV media disk (3.7T) | `/srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886` |
| OMV downloads disk (1.4T) | `/srv/dev-disk-by-uuid-b6591cb4-4cc4-4901-aaa2-4feabab33235` |
| arr-box hostname | `arr-box.local` / `192.168.1.162` |
| arr-box NetBird | `arr-box.netbird.cloud` / `100.96.191.232` |

| arrbox service user | UID `1100` / GID `1100` |
| MacBook media | `/Users/wojciechgula/Media` (TV: 185G, Movies: 54G) |
| GitHub repo | `gulasz101/arr-stack` (private, to be created) |

---

## Phase 1: GitHub Repository Setup

### Task 1: Create private GitHub repository and push

**Files:**
- Modify: `.gitignore`

**Step 1: Create private repo on GitHub**

```bash
gh repo create gulasz101/arr-stack --private --source=. --remote=origin --push
```

Expected output: `✓ Created repository gulasz101/arr-stack on GitHub`

**Step 2: Verify remote is set**

```bash
git remote -v
```

Expected:
```
origin  git@github.com:gulasz101/arr-stack.git (fetch)
origin  git@github.com:gulasz101/arr-stack.git (push)
```

**Step 3: Verify repo is private**

```bash
gh repo view gulasz101/arr-stack --json visibility -q .visibility
```

Expected: `PRIVATE`

**Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: initial push to private GitHub repo"
git push -u origin main
```

---

## Phase 2: MacBook Tooling Setup

### Task 2: Install sops, age, and just on MacBook

**Step 1: Install tools**

```bash
brew install age sops just
```

**Step 2: Verify installations**

```bash
age --version && sops --version && just --version
```

Expected (approximately):
```
age v1.2.x
sops 3.x.x
just 1.x.x
```

No commit needed — local tooling only.

---

## Phase 3: SOPS + age Secrets Encryption

### Task 3: Generate age key and encrypt .env

**Files:**
- Create: `.sops.yaml`
- Create: `.env.sops` (encrypted, committed to git)
- Modify: `.gitignore` (allow `.env.sops`, `.sops.yaml`)

**Step 1: Generate age key pair**

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Expected output (last line):
```
Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Copy the public key — you'll need it in the next step.

**Step 2: Save private key to 1Password**

Open 1Password → create vault "Homelab" (if it doesn't exist) → create new item:
- Type: Secure Note
- Title: `arr-stack age key`
- Field: `private_key` = contents of `~/.config/sops/age/keys.txt`

Also note the public key separately:
```bash
cat ~/.config/sops/age/keys.txt | grep "^# public key:" | sed 's/# public key: //'
```

**Step 3: Create `.sops.yaml`**

```bash
# Replace age1xxx... with your actual public key from Step 1
cat > /Users/wojciechgula/Projects/arr-stack/.sops.yaml << 'EOF'
creation_rules:
  - path_regex: \.env$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF
```

Edit `.sops.yaml` and replace the placeholder with your actual public key.

**Step 4: Verify `.sops.yaml` syntax**

```bash
cat /Users/wojciechgula/Projects/arr-stack/.sops.yaml
```

Expected: should show your actual age public key (starts with `age1...`).

**Step 5: Encrypt .env to .env.sops**

```bash
cd /Users/wojciechgula/Projects/arr-stack
sops -e .env > .env.sops
```

**Step 6: Verify encryption worked**

```bash
# Should show encrypted content (not plaintext)
head -5 .env.sops

# Should decrypt successfully
sops -d .env.sops | head -3
```

Expected: `head -5` shows SOPS metadata JSON/YAML wrapper, `sops -d` shows plaintext env vars.

**Step 7: Update .gitignore to allow .env.sops**

The `.env` is already gitignored. Add explicit allowlist for `.env.sops`:

Edit `.gitignore` — find the `# Environment file with secrets` section and update:

```
# Environment file with secrets — NEVER commit plaintext
.env

# Encrypted secrets — safe to commit
# .env.sops is intentionally tracked
```

**Step 8: Commit**

```bash
cd /Users/wojciechgula/Projects/arr-stack
git add .sops.yaml .env.sops .gitignore
git commit -m "sops: add age encryption config and encrypted .env

Secrets encrypted with age. Master key stored in 1Password vault
'Homelab', item 'arr-stack age key'. Decrypt with: sops -d .env.sops"
git push
```

---

## Phase 4: docker-compose.yml Updates

### Task 4: Update compose for arr-box (PUID/PGID, NFS paths, container networking)

**Files:**
- Modify: `docker-compose.yml`
- Modify: `.env.example`

**Step 1: Write verification — what the updated compose should declare**

The updated compose must:
- Use `PUID=1100` / `PGID=1100` defaults (was 501/20)
- Use `/mnt/media` for media (was `${MEDIA_PATH}`)
- Use `/mnt/downloads` for downloads (was `${DOWNLOAD_PATH}`)
- Remove `host.docker.internal` references in favour of container-name routing
- Update `JELLYFIN_PublishedServerUrl` to use arr-box hostnames

**Step 2: Update docker-compose.yml**

Replace the entire `docker-compose.yml` with the arr-box-optimised version:

Key changes:
- `PUID=${PUID:-1100}` and `PGID=${PGID:-1100}` everywhere
- `${DOWNLOAD_PATH:-/mnt/downloads}` for download paths
- `${MEDIA_PATH:-/mnt/media}` for media paths
- Jellyfin `JELLYFIN_PublishedServerUrl=http://jellyfin.${ARR_HOSTNAME_LOCAL:-arr-box.local}`
- Homepage `HOMEPAGE_ALLOWED_HOSTS=${ARR_HOSTNAME_LOCAL:-arr-box.local},${ARR_HOSTNAME_NETBIRD:-arr-box.netbird.cloud},localhost`

Full file content:

```yaml
# ===========================================
# 🏴‍☠️ Arr Stack - Home Media Server
# ===========================================
# Access via Caddy reverse proxy:
#   Local:   http://arr-box.local           (Dashboard)
#   NetBird: http://arr-box.netbird.cloud   (Dashboard)
#   Subdomain examples:
#     http://jellyfin.arr-box.local
#     http://jellyfin.arr-box.netbird.cloud
# ===========================================

services:
  # ===========================================
  # Caddy - Reverse Proxy
  # ===========================================
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    ports:
      - "80:80"
    volumes:
      - ./config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./config/caddy/data:/data
      - ./config/caddy/config:/config
    environment:
      - TZ=${TZ:-Europe/Berlin}
    restart: unless-stopped

  # ===========================================
  # GLUETUN - VPN Container (Mullvad WireGuard)
  # ===========================================
  gluetun:
    image: qmcgaw/gluetun:v3
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - 8080:8080   # qBittorrent WebUI
      - 6881:6881   # qBittorrent torrent port
      - 6881:6881/udp
      - 9696:9696   # Prowlarr
      - 8989:8989   # Sonarr
      - 7878:7878   # Radarr
      - 8191:8191   # FlareSolverr
    environment:
      - VPN_SERVICE_PROVIDER=mullvad
      - VPN_TYPE=wireguard
      - WIREGUARD_PRIVATE_KEY=${MULLVAD_PRIVATE_KEY}
      - WIREGUARD_ADDRESSES=${MULLVAD_ADDRESS}
      - SERVER_COUNTRIES=${VPN_COUNTRY:-Spain}
      - FIREWALL_OUTBOUND_SUBNETS=${LAN_SUBNET:-192.168.1.0/24}
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - ./config/gluetun:/gluetun
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/gluetun-entrypoint", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ===========================================
  # qBittorrent
  # ===========================================
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    environment:
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - TZ=${TZ:-Europe/Berlin}
      - WEBUI_PORT=8080
      - TORRENTING_PORT=6881
    volumes:
      - ./config/qbittorrent:/config
      - ${DOWNLOAD_PATH:-/mnt/downloads}:/downloads
    restart: unless-stopped

  # ===========================================
  # Prowlarr - Indexer manager
  # ===========================================
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    environment:
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - ./config/prowlarr:/config
    restart: unless-stopped

  # ===========================================
  # Sonarr - TV Series
  # ===========================================
  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    environment:
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - ./config/sonarr:/config
      - ${DOWNLOAD_PATH:-/mnt/downloads}:/downloads
      - ${MEDIA_PATH:-/mnt/media}/tv:/tv
    restart: unless-stopped

  # ===========================================
  # Radarr - Movies
  # ===========================================
  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    environment:
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - ./config/radarr:/config
      - ${DOWNLOAD_PATH:-/mnt/downloads}:/downloads
      - ${MEDIA_PATH:-/mnt/media}/movies:/movies
    restart: unless-stopped

  # ===========================================
  # Bazarr - Subtitles
  # ===========================================
  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: bazarr
    ports:
      - 6767:6767
    environment:
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - ./config/bazarr:/config
      - ${MEDIA_PATH:-/mnt/media}/tv:/tv
      - ${MEDIA_PATH:-/mnt/media}/movies:/movies
    depends_on:
      - sonarr
      - radarr
    restart: unless-stopped

  # ===========================================
  # Homepage - Dashboard
  # ===========================================
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    ports:
      - 3000:3000
    environment:
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - HOMEPAGE_ALLOWED_HOSTS=${ARR_HOSTNAME_LOCAL:-arr-box.local},${ARR_HOSTNAME_NETBIRD:-arr-box.netbird.cloud},localhost
      - HOMEPAGE_VAR_SONARR_API_KEY=${SONARR_API_KEY}
      - HOMEPAGE_VAR_RADARR_API_KEY=${RADARR_API_KEY}
      - HOMEPAGE_VAR_PROWLARR_API_KEY=${PROWLARR_API_KEY}
      - HOMEPAGE_VAR_BAZARR_API_KEY=${BAZARR_API_KEY}
      - HOMEPAGE_VAR_JELLYFIN_API_KEY=${JELLYFIN_API_KEY}
      - HOMEPAGE_VAR_QBITTORRENT_PASSWORD=${QBITTORRENT_PASSWORD}
    volumes:
      - ./config/homepage:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped

  # ===========================================
  # FlareSolverr - Bypass Cloudflare protection
  # ===========================================
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    environment:
      - LOG_LEVEL=info
      - TZ=${TZ:-Europe/Berlin}
    restart: unless-stopped

  # ===========================================
  # Jellyfin - Media Server
  # ===========================================
  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    container_name: jellyfin
    ports:
      - 8096:8096
    environment:
      - PUID=${PUID:-1100}
      - PGID=${PGID:-1100}
      - TZ=${TZ:-Europe/Berlin}
      - JELLYFIN_PublishedServerUrl=http://jellyfin.${ARR_HOSTNAME_LOCAL:-arr-box.local}
    volumes:
      - ./config/jellyfin:/config
      - ${MEDIA_PATH:-/mnt/media}/tv:/data/tvshows
      - ${MEDIA_PATH:-/mnt/media}/movies:/data/movies
    restart: unless-stopped
```

**Step 3: Update .env.example**

Add/update these variables in `.env.example`:

```bash
# ===========================================
# Reverse Proxy Hostnames
# ===========================================
# Local mDNS hostname of arr-box
ARR_HOSTNAME_LOCAL=arr-box.local
# NetBird VPN hostname of arr-box
ARR_HOSTNAME_NETBIRD=arr-box.netbird.cloud

# ===========================================
# Paths (NFS mounts on arr-box)
# ===========================================
DOWNLOAD_PATH=/mnt/downloads
MEDIA_PATH=/mnt/media

# ===========================================
# User/Group IDs
# Linux: match arrbox service user (UID 1100 / GID 1100)
# ===========================================
PUID=1100
PGID=1100
```

Remove the old `ARR_HOSTNAME` variable.

**Step 4: Re-encrypt .env.sops with updated values**

The `.env` on the MacBook still has old values. Before encrypting the final version:

```bash
# Edit .env to update the new variables
# Change: ARR_HOSTNAME=... → ARR_HOSTNAME_LOCAL=arr-box.local
# Add:    ARR_HOSTNAME_NETBIRD=arr-box.netbird.cloud
# Change: PUID=501 → PUID=1100
# Change: PGID=20 → PGID=1100
# Change: MEDIA_PATH=... → MEDIA_PATH=/mnt/media
# Change: DOWNLOAD_PATH=... → DOWNLOAD_PATH=/mnt/downloads

# Re-encrypt
sops -e .env > .env.sops
```

**Step 5: Commit**

```bash
git add docker-compose.yml .env.example .env.sops
git commit -m "feat(compose): update for arr-box — NFS paths, PUID 1100, dual hostname

- PUID/PGID changed from 501/20 to 1100/1100 (arrbox service user)
- MEDIA_PATH → /mnt/media (NFS mount from OMV 3.7T disk)
- DOWNLOAD_PATH → /mnt/downloads (NFS mount from OMV 1.4T disk)
- ARR_HOSTNAME split into ARR_HOSTNAME_LOCAL + ARR_HOSTNAME_NETBIRD
- Update .env.sops with new variable names"
git push
```

---

## Phase 5: Caddy Configuration

### Task 5: Update Caddyfile for dual-hostname routing

**Files:**
- Modify: `config/caddy/Caddyfile`

**Step 1: Replace Caddyfile**

```caddyfile
# ===========================================
# 🏴‍☠️ Arr Stack - Caddy Reverse Proxy
# ===========================================
# Serves both local (.local) and NetBird (.netbird.cloud) domains.
# Auto-HTTPS disabled — plain HTTP for LAN use.
# ===========================================

{
	auto_https off
}

# ---- Dashboard ----
http://arr-box.local, http://arr-box.netbird.cloud {
	reverse_proxy homepage:3000
}

# ---- Jellyfin ----
http://jellyfin.arr-box.local, http://jellyfin.arr-box.netbird.cloud {
	reverse_proxy jellyfin:8096
}

# ---- Sonarr (behind gluetun VPN) ----
http://sonarr.arr-box.local, http://sonarr.arr-box.netbird.cloud {
	reverse_proxy gluetun:8989
}

# ---- Radarr (behind gluetun VPN) ----
http://radarr.arr-box.local, http://radarr.arr-box.netbird.cloud {
	reverse_proxy gluetun:7878
}

# ---- Prowlarr (behind gluetun VPN) ----
http://prowlarr.arr-box.local, http://prowlarr.arr-box.netbird.cloud {
	reverse_proxy gluetun:9696
}

# ---- qBittorrent (behind gluetun VPN) ----
http://qbit.arr-box.local, http://qbit.arr-box.netbird.cloud {
	reverse_proxy gluetun:8080
}

# ---- Bazarr ----
http://bazarr.arr-box.local, http://bazarr.arr-box.netbird.cloud {
	reverse_proxy bazarr:6767
}
```

Note: Caddy now uses container names (`homepage:3000`, `gluetun:8989`) instead of `host.docker.internal`. All services with `network_mode: "service:gluetun"` are reachable via the `gluetun` container name.

Note: The Caddyfile no longer uses `${ARR_HOSTNAME}` env var — hostnames are hardcoded as `arr-box.local` and `arr-box.netbird.cloud`. These are stable and won't change.

**Step 2: Commit**

```bash
git add config/caddy/Caddyfile
git commit -m "feat(caddy): add dual-hostname routing for .local and .netbird.cloud

Both arr-box.local and arr-box.netbird.cloud (plus subdomains) are
served from the same Caddy instance. Container names used directly
instead of host.docker.internal."
git push
```

---

## Phase 6: Homepage Configuration

### Task 6: Update homepage service URLs for container networking

**Files:**
- Modify: `config/homepage/services.yaml`

**Step 1: Update services.yaml**

Services now communicate container-to-container, not via `host.docker.internal`. Links shown to the user use the `.local` subdomain URLs:

```yaml
# Services configuration
# Container-to-container routing via Docker network
---
- Media Management:
    - Sonarr:
        icon: sonarr.png
        href: http://sonarr.arr-box.local
        description: TV Series
        widget:
          type: sonarr
          url: http://gluetun:8989
          key: {{HOMEPAGE_VAR_SONARR_API_KEY}}

    - Radarr:
        icon: radarr.png
        href: http://radarr.arr-box.local
        description: Movies
        widget:
          type: radarr
          url: http://gluetun:7878
          key: {{HOMEPAGE_VAR_RADARR_API_KEY}}

    - Prowlarr:
        icon: prowlarr.png
        href: http://prowlarr.arr-box.local
        description: Indexer Manager
        widget:
          type: prowlarr
          url: http://gluetun:9696
          key: {{HOMEPAGE_VAR_PROWLARR_API_KEY}}

- Downloads:
    - qBittorrent:
        icon: qbittorrent.png
        href: http://qbit.arr-box.local
        description: Torrent Client
        widget:
          type: qbittorrent
          url: http://gluetun:8080
          username: admin
          password: {{HOMEPAGE_VAR_QBITTORRENT_PASSWORD}}

    - Bazarr:
        icon: bazarr.png
        href: http://bazarr.arr-box.local
        description: Subtitles
        widget:
          type: bazarr
          url: http://bazarr:6767
          key: {{HOMEPAGE_VAR_BAZARR_API_KEY}}

- Streaming:
    - Jellyfin:
        icon: jellyfin.png
        href: http://jellyfin.arr-box.local
        description: Media Server
        widget:
          type: jellyfin
          url: http://jellyfin:8096
          key: {{HOMEPAGE_VAR_JELLYFIN_API_KEY}}
          enableBlocks: true
```

**Step 2: Commit**

```bash
git add config/homepage/services.yaml
git commit -m "feat(homepage): update service URLs for arr-box container networking

- href links updated to arr-box.local subdomain URLs
- widget URLs updated from host.docker.internal to container names
- gluetun used as hostname for VPN-routed services (sonarr/radarr/prowlarr/qbit)"
git push
```

---

## Phase 7: justfile

### Task 7: Create deployment justfile

**Files:**
- Create: `justfile`

**Step 1: Create justfile**

```makefile
# ===========================================
# 🏴‍☠️ Arr Stack - Task Runner
# ===========================================
# Prerequisites: sops, age, docker, docker compose
# Usage: just <command>
# ===========================================

# Show available commands
default:
    @just --list

# Decrypt .env.sops → .env (requires age key at ~/.config/sops/age/keys.txt)
decrypt:
    sops -d .env.sops > .env
    @echo "✓ .env decrypted"

# Encrypt .env → .env.sops (requires .sops.yaml with your age public key)
encrypt:
    sops -e .env > .env.sops
    @echo "✓ .env.sops encrypted — safe to commit"

# Edit encrypted secrets in-place (sops handles decrypt/re-encrypt)
secrets:
    sops .env.sops

# Deploy: decrypt + start/update stack
deploy: decrypt
    docker compose up -d
    @echo "✓ Stack deployed"

# Update: pull latest images + redeploy
update: decrypt
    docker compose pull
    docker compose up -d
    @echo "✓ Stack updated"

# Show running containers
status:
    docker compose ps

# Show live logs (all containers)
logs:
    docker compose logs -f

# Show logs for a specific service: just log sonarr
log service:
    docker compose logs -f {{service}}

# Stop the stack
stop:
    docker compose down
    @echo "✓ Stack stopped"

# Hard reset: stop + remove volumes (WARNING: destroys config!)
reset:
    @echo "WARNING: This will destroy all container config data!"
    @read -p "Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
    docker compose down -v

# Pull latest code + redeploy (run on arr-box after git pull)
pull-deploy:
    git pull
    just deploy
```

**Step 2: Commit**

```bash
git add justfile
git commit -m "feat: add justfile for deployment commands

Commands: decrypt, encrypt, secrets, deploy, update, status, logs,
log <service>, stop, reset, pull-deploy"
git push
```

---

## Phase 8: OpenMediaVault Setup

### Task 8: Create arrbox user on OMV

**Step 1: SSH into OMV and create user**

```bash
ssh openmediavault
```

Then on OMV:

```bash
# Create group first with specific GID
sudo groupadd --gid 1100 arrbox

# Create user with specific UID, same GID, no login shell (service user)
sudo useradd \
  --uid 1100 \
  --gid 1100 \
  --no-create-home \
  --shell /usr/sbin/nologin \
  --comment "arr-stack service user" \
  arrbox
```

**Step 2: Verify user created correctly**

```bash
id arrbox
```

Expected:
```
uid=1100(arrbox) gid=1100(arrbox) groups=1100(arrbox)
```

### Task 9: Create directory structure on OMV disks

Still on OMV:

**Step 1: Create media directories on 3.7T disk**

```bash
# Short alias for the UUID path
MEDIA_DISK="/srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886"

sudo mkdir -p "$MEDIA_DISK/media/tv"
sudo mkdir -p "$MEDIA_DISK/media/movies"

# Set ownership to arrbox
sudo chown -R arrbox:arrbox "$MEDIA_DISK/media"
sudo chmod -R 755 "$MEDIA_DISK/media"
```

**Step 2: Create downloads directory on 1.4T disk**

```bash
DOWNLOADS_DISK="/srv/dev-disk-by-uuid-b6591cb4-4cc4-4901-aaa2-4feabab33235"

sudo mkdir -p "$DOWNLOADS_DISK/downloads"
sudo chown -R arrbox:arrbox "$DOWNLOADS_DISK/downloads"
sudo chmod -R 755 "$DOWNLOADS_DISK/downloads"
```

**Step 3: Verify directories exist with correct ownership**

```bash
ls -la /srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886/media/
ls -la /srv/dev-disk-by-uuid-b6591cb4-4cc4-4901-aaa2-4feabab33235/
```

Expected:
```
drwxr-xr-x  4 arrbox arrbox 4096 ... media
drwxr-xr-x  2 arrbox arrbox 4096 ... tv
drwxr-xr-x  2 arrbox arrbox 4096 ... movies
...
drwxr-xr-x  2 arrbox arrbox 4096 ... downloads
```

### Task 10: Configure NFS exports on OMV

Still on OMV:

**Step 1: Install NFS kernel server if not present**

```bash
dpkg -l | grep nfs-kernel-server || sudo apt-get install -y nfs-kernel-server
```

**Step 2: Create arr-stack NFS exports file**

Using `/etc/exports.d/` to avoid OMV overwriting `/etc/exports`:

```bash
sudo tee /etc/exports.d/arr-stack.exports << 'EOF'
# arr-stack NFS exports
# Media library (3.7T disk) — arr-box only
/srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886/media 192.168.1.162(rw,sync,no_root_squash,no_subtree_check,all_squash,anonuid=1100,anongid=1100)

# Downloads (1.4T disk) — arr-box only
/srv/dev-disk-by-uuid-b6591cb4-4cc4-4901-aaa2-4feabab33235/downloads 192.168.1.162(rw,sync,no_root_squash,no_subtree_check,all_squash,anonuid=1100,anongid=1100)
EOF
```

Explanation of options:
- `all_squash,anonuid=1100,anongid=1100` — all access is mapped to arrbox UID/GID regardless of caller
- `no_root_squash` — allows root on arr-box to manage files if needed
- `sync` — writes confirmed before acknowledging (safer for media)

**Step 3: Apply exports**

```bash
sudo exportfs -ra
```

**Step 4: Verify exports are active**

```bash
sudo exportfs -v
```

Expected output shows both exports with arr-box IP.

**Step 5: Verify NFS service is running**

```bash
sudo systemctl status nfs-kernel-server
```

Expected: `active (running)`

### Task 11: Install Copyparty on OMV (permanent service)

Still on OMV:

**Step 1: Install Python pip if needed, then copyparty**

```bash
# Check Python version (OMV has Python 3)
python3 --version

# Install pip if needed
sudo apt-get install -y python3-pip python3-venv

# Install copyparty for arrbox user
sudo -u arrbox python3 -m pip install --user copyparty
```

**Step 2: Verify copyparty installed**

```bash
sudo -u arrbox /home/arrbox/.local/bin/copyparty --version 2>/dev/null || \
  python3 -m copyparty --version
```

Note: If arrbox has no home dir, install system-wide: `sudo pip3 install copyparty`

**Step 3: Create systemd service for copyparty**

```bash
sudo tee /etc/systemd/system/copyparty.service << 'EOF'
[Unit]
Description=Copyparty File Server
After=network.target

[Service]
Type=simple
User=arrbox
WorkingDirectory=/srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886
ExecStart=/usr/local/bin/copyparty \
  --port 3923 \
  --auth arrbox:CHANGEME_SET_PASSWORD \
  /srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886/media
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

**Step 4: Set copyparty password**

Edit the service file to set a real password:
```bash
sudo nano /etc/systemd/system/copyparty.service
# Change CHANGEME_SET_PASSWORD to a real password
# Example: --auth arrbox:mediaserver2026
```

**Step 5: Enable and start copyparty**

```bash
sudo systemctl daemon-reload
sudo systemctl enable copyparty
sudo systemctl start copyparty
```

**Step 6: Verify copyparty is running**

```bash
sudo systemctl status copyparty
curl -s -o /dev/null -w "%{http_code}" http://localhost:3923/
```

Expected: HTTP 200 (or 401 if auth is required on root)

**Step 7: Test from MacBook**

```bash
# From MacBook:
curl -s -o /dev/null -w "%{http_code}" http://openmediavault.local:3923/
```

Expected: 200 or 401 — confirms port is reachable across LAN.

---

## Phase 9: arr-box System Setup

### Task 12: Create arrbox user on arr-box

**SSH into arr-box:**

```bash
ssh arr-box
```

Then:

```bash
# Create group with GID 1100
sudo groupadd --gid 1100 arrbox

# Create user with UID 1100
sudo useradd \
  --uid 1100 \
  --gid 1100 \
  --home-dir /home/arrbox \
  --create-home \
  --shell /bin/bash \
  --comment "arr-stack service user" \
  arrbox

# Add arrbox to sudo (needed to install systemd service)
sudo usermod -aG sudo arrbox
```

**Verify:**

```bash
id arrbox
```

Expected:
```
uid=1100(arrbox) gid=1100(arrbox) groups=1100(arrbox),27(sudo)
```

### Task 13: Install Docker on arr-box

Still on arr-box (as gulasz101):

**Step 1: Install Docker Engine via official repo**

```bash
# Add Docker's GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repo
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

**Step 2: Add arrbox to docker group**

```bash
sudo usermod -aG docker arrbox
```

**Step 3: Enable and start Docker**

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

**Step 4: Verify Docker works**

```bash
sudo docker run --rm hello-world
```

Expected: `Hello from Docker!`

**Step 5: Verify as arrbox user (requires re-login)**

```bash
sudo -u arrbox docker info | grep "Server Version"
```

Expected: shows a Docker version number without permission errors.

### Task 14: Install just, age, and sops on arr-box

Still on arr-box:

**Step 1: Install just**

```bash
# Download latest just binary for Linux amd64
JUST_VERSION=$(curl -s https://api.github.com/repos/casey/just/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
curl -sL "https://github.com/casey/just/releases/download/v${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  | sudo tar xz -C /usr/local/bin just
sudo chmod +x /usr/local/bin/just
```

**Step 2: Install age**

```bash
AGE_VERSION=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
curl -sL "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz" \
  | sudo tar xz -C /tmp
sudo cp /tmp/age/age /usr/local/bin/age
sudo cp /tmp/age/age-keygen /usr/local/bin/age-keygen
```

**Step 3: Install sops**

```bash
SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
sudo curl -sL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" \
  -o /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

**Step 4: Verify all three tools**

```bash
just --version && age --version && sops --version
```

Expected: version strings for all three, no errors.

### Task 15: Configure NFS mounts on arr-box

Still on arr-box:

**Step 1: Install NFS client**

```bash
sudo apt-get install -y nfs-common
```

**Step 2: Create mount points**

```bash
sudo mkdir -p /mnt/media
sudo mkdir -p /mnt/downloads
```

**Step 3: Test NFS connection before adding to fstab**

```bash
# Test mount manually first
sudo mount -t nfs \
  openmediavault.local:/srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886/media \
  /mnt/media

sudo mount -t nfs \
  openmediavault.local:/srv/dev-disk-by-uuid-b6591cb4-4cc4-4901-aaa2-4feabab33235/downloads \
  /mnt/downloads
```

**Step 4: Verify NFS mounts work**

```bash
df -h | grep mnt
ls /mnt/media
ls /mnt/downloads
```

Expected: mount entries show, directories listing (tv/ movies/ in media).

**Step 5: Test write access**

```bash
touch /mnt/media/tv/.arr-box-test && echo "Write OK" && rm /mnt/media/tv/.arr-box-test
```

Expected: `Write OK`

**Step 6: Unmount test mounts**

```bash
sudo umount /mnt/media
sudo umount /mnt/downloads
```

**Step 7: Add to /etc/fstab for permanent mounts**

```bash
sudo tee -a /etc/fstab << 'EOF'
# arr-stack NFS mounts from openmediavault.local
openmediavault.local:/srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886/media     /mnt/media      nfs  defaults,_netdev,soft,timeo=30  0 0
openmediavault.local:/srv/dev-disk-by-uuid-b6591cb4-4cc4-4901-aaa2-4feabab33235/downloads /mnt/downloads  nfs  defaults,_netdev,soft,timeo=30  0 0
EOF
```

**Step 8: Verify fstab mounts**

```bash
sudo mount -a
df -h | grep mnt
```

Expected: both mounts appear in `df -h`.

---

## Phase 10: arr-box Application Deployment

### Task 16: Install age key from 1Password on arr-box

On arr-box, as the `arrbox` user:

```bash
sudo -u arrbox bash
mkdir -p ~/.config/sops/age
```

Retrieve the age private key from 1Password (on your MacBook):

```bash
# On MacBook — copy the private key content
cat ~/.config/sops/age/keys.txt
```

Paste it into arr-box:

```bash
# On arr-box, as arrbox user
cat > ~/.config/sops/age/keys.txt << 'EOF'
# created: 2026-02-22T...
# public key: age1xxxxx...
AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
EOF
chmod 600 ~/.config/sops/age/keys.txt
```

**Verify:**

```bash
# Should not error
sops -d /tmp/test.sops 2>/dev/null || echo "key loaded (error is expected for missing file)"
```

### Task 17: Clone repo and deploy stack on arr-box

On arr-box, as the `arrbox` user:

**Step 1: Set up GitHub SSH access**

```bash
# Generate SSH key for arrbox on arr-box
sudo -u arrbox ssh-keygen -t ed25519 -C "arrbox@arr-box" -f /home/arrbox/.ssh/id_ed25519 -N ""

# Display public key
cat /home/arrbox/.ssh/id_ed25519.pub
```

**Step 2: Add deploy key to GitHub (on MacBook)**

```bash
# On MacBook:
gh repo deploy-key add /dev/stdin --title "arr-box arrbox user" --repo gulasz101/arr-stack << 'EOF'
<paste the public key from step 1 here>
EOF
```

**Step 3: Clone repo on arr-box**

```bash
sudo -u arrbox bash -c "
  git clone git@github.com:gulasz101/arr-stack.git /opt/arr-stack
"
```

**Step 4: Decrypt secrets**

```bash
cd /opt/arr-stack
sudo -u arrbox just decrypt
```

Expected: `.env` created, no errors.

**Step 5: Verify .env looks correct**

```bash
sudo -u arrbox grep -E "^(PUID|PGID|MEDIA_PATH|DOWNLOAD_PATH|ARR_HOSTNAME)" /opt/arr-stack/.env
```

Expected:
```
PUID=1100
PGID=1100
MEDIA_PATH=/mnt/media
DOWNLOAD_PATH=/mnt/downloads
ARR_HOSTNAME_LOCAL=arr-box.local
ARR_HOSTNAME_NETBIRD=arr-box.netbird.cloud
```

**Step 6: Deploy the stack**

```bash
sudo -u arrbox bash -c "cd /opt/arr-stack && just deploy"
```

**Step 7: Verify all containers are running**

```bash
sudo -u arrbox bash -c "cd /opt/arr-stack && just status"
```

Expected: All containers show `Up` status (gluetun may take 30s to become healthy).

**Step 8: Verify VPN is connected**

```bash
docker exec gluetun wget -qO- https://api.ipify.org
```

Expected: IP address in Spain (not your home IP).

**Step 9: Test dashboard access from MacBook**

```bash
# From MacBook:
curl -s -o /dev/null -w "%{http_code}" http://arr-box.local
```

Expected: `200`

### Task 18: Install systemd autostart service on arr-box

On arr-box (as gulasz101 with sudo):

**Step 1: Create systemd service**

```bash
sudo tee /etc/systemd/system/arr-stack.service << 'EOF'
[Unit]
Description=Arr Stack Media Server
Documentation=https://github.com/gulasz101/arr-stack
After=network-online.target remote-fs.target docker.service
Requires=remote-fs.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=arrbox
Group=arrbox
WorkingDirectory=/opt/arr-stack
ExecStartPre=/usr/local/bin/sops -d /opt/arr-stack/.env.sops --output /opt/arr-stack/.env
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF
```

**Step 2: Set SOPS_AGE_KEY_FILE for the service**

The service needs to know where the age key is. Add environment to the service:

```bash
sudo mkdir -p /etc/systemd/system/arr-stack.service.d
sudo tee /etc/systemd/system/arr-stack.service.d/env.conf << 'EOF'
[Service]
Environment="SOPS_AGE_KEY_FILE=/home/arrbox/.config/sops/age/keys.txt"
EOF
```

**Step 3: Enable the service**

```bash
sudo systemctl daemon-reload
sudo systemctl enable arr-stack.service
```

**Step 4: Stop the stack (deployed manually in Task 17) and restart via systemd**

```bash
# Stop manually-started stack
sudo -u arrbox bash -c "cd /opt/arr-stack && docker compose down"

# Start via systemd
sudo systemctl start arr-stack.service
```

**Step 5: Verify service started correctly**

```bash
sudo systemctl status arr-stack.service
sudo -u arrbox bash -c "cd /opt/arr-stack && docker compose ps"
```

Expected: service shows `active (exited)` (oneshot type), all containers `Up`.

**Step 6: Commit systemd service file to repo**

```bash
# On MacBook:
mkdir -p /Users/wojciechgula/Projects/arr-stack/deploy
cat > /Users/wojciechgula/Projects/arr-stack/deploy/arr-stack.service << 'EOF'
<same content as above>
EOF

git add deploy/arr-stack.service deploy/
git commit -m "feat(systemd): add arr-stack.service autostart unit

Starts after NFS mounts (remote-fs.target) and Docker.
Decrypts .env.sops via sops before starting docker compose.
Enabled with: systemctl enable arr-stack.service"
git push
```

---

## Phase 11: Config Migration

### Task 19: Migrate service configs from MacBook to arr-box

The `config/` dirs (sonarr, radarr, prowlarr, bazarr, qbittorrent, jellyfin) are gitignored because they contain API keys and user data. They must be copied directly.

**Step 1: Stop MacBook arr-stack**

```bash
cd /Users/wojciechgula/Projects/arr-stack
docker compose down
```

**Step 2: Copy config directories from MacBook to arr-box**

```bash
# From MacBook — rsync config dirs to arr-box
rsync -avz --progress \
  /Users/wojciechgula/Projects/arr-stack/config/sonarr/ \
  arrbox@arr-box:/opt/arr-stack/config/sonarr/

rsync -avz --progress \
  /Users/wojciechgula/Projects/arr-stack/config/radarr/ \
  arrbox@arr-box:/opt/arr-stack/config/radarr/

rsync -avz --progress \
  /Users/wojciechgula/Projects/arr-stack/config/prowlarr/ \
  arrbox@arr-box:/opt/arr-stack/config/prowlarr/

rsync -avz --progress \
  /Users/wojciechgula/Projects/arr-stack/config/qbittorrent/ \
  arrbox@arr-box:/opt/arr-stack/config/qbittorrent/

rsync -avz --progress \
  /Users/wojciechgula/Projects/arr-stack/config/bazarr/ \
  arrbox@arr-box:/opt/arr-stack/config/bazarr/

rsync -avz --progress \
  /Users/wojciechgula/Projects/arr-stack/config/jellyfin/ \
  arrbox@arr-box:/opt/arr-stack/config/jellyfin/
```

**Step 3: Fix ownership on arr-box**

```bash
# On arr-box:
sudo chown -R arrbox:arrbox /opt/arr-stack/config/
```

**Step 4: Restart stack on arr-box**

```bash
# On arr-box:
sudo systemctl restart arr-stack.service
sleep 30
sudo -u arrbox bash -c "cd /opt/arr-stack && just status"
```

All containers should be `Up`.

---

## Phase 12: Media Migration (Copyparty)

### Task 20: Install copyparty on MacBook

```bash
pip3 install copyparty
# or: pipx install copyparty
```

**Verify:**

```bash
copyparty --version
```

### Task 21: Migrate TV shows from MacBook → OMV (185G)

Copyparty uploads in parallel chunks, saturating LAN bandwidth.

**Step 1: Start upload**

```bash
# From MacBook
# Upload to the /tv subfolder under media
copyparty-client \
  --host openmediavault.local \
  --port 3923 \
  --user arrbox \
  --pass "YOUR_COPYPARTY_PASSWORD" \
  --upload-to /tv \
  --jobs 8 \
  /Users/wojciechgula/Media/tv/
```

Monitor progress in the copyparty web UI: `http://openmediavault.local:3923`

**Step 2: Verify TV file count matches**

```bash
# On MacBook: count source files
find /Users/wojciechgula/Media/tv -type f | wc -l

# On OMV (via SSH):
find /srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886/media/tv -type f | wc -l
```

Expected: counts match.

### Task 22: Migrate Movies from MacBook → OMV (54G)

```bash
copyparty-client \
  --host openmediavault.local \
  --port 3923 \
  --user arrbox \
  --pass "YOUR_COPYPARTY_PASSWORD" \
  --upload-to /movies \
  --jobs 8 \
  /Users/wojciechgula/Media/movies/
```

**Verify:**

```bash
# Count source
find /Users/wojciechgula/Media/movies -type f | wc -l

# Count destination (on OMV)
find /srv/dev-disk-by-uuid-cda9bf6e-0ed1-4e61-b063-1cbab7351886/media/movies -type f | wc -l
```

---

## Phase 13: Cutover and Verification

### Task 23: Trigger Jellyfin library scan on arr-box

After media migration completes:

**Step 1: Open Jellyfin on arr-box**

```
http://jellyfin.arr-box.local
```

**Step 2: Trigger full library scan**

Dashboard → Libraries → click "Scan All Libraries" button (or go to each library and scan).

Wait for scan to complete (watch progress in Dashboard).

**Step 3: Verify library counts**

Check that number of TV shows and movies in Jellyfin matches what you had on the MacBook.

### Task 24: Verify all services from local network

From MacBook browser (same LAN):

| Check | URL | Expected |
|---|---|---|
| Dashboard | `http://arr-box.local` | Homepage dashboard loads |
| Jellyfin | `http://jellyfin.arr-box.local` | Media library visible |
| Sonarr | `http://sonarr.arr-box.local` | Shows list visible |
| Radarr | `http://radarr.arr-box.local` | Movies list visible |
| Prowlarr | `http://prowlarr.arr-box.local` | Indexers page loads |
| qBittorrent | `http://qbit.arr-box.local` | WebUI loads |
| Bazarr | `http://bazarr.arr-box.local` | Subtitles page loads |

### Task 25: Verify NetBird access

From a device connected to NetBird (phone or VPN peer):

| Check | URL | Expected |
|---|---|---|
| Dashboard | `http://arr-box.netbird.cloud` | Homepage dashboard loads |
| Jellyfin | `http://jellyfin.arr-box.netbird.cloud` | Library visible |

### Task 26: Verify Android TV Jellyfin app

1. Open Jellyfin app on Android TV
2. Remove the old MacBook server if present
3. Add new server: `http://arr-box.local` or `http://jellyfin.arr-box.local`
4. Log in with existing credentials
5. Verify watch history is preserved (progress on shows/movies)

### Task 27: Final commit — migration complete

```bash
cat >> /Users/wojciechgula/Projects/arr-stack/docs/plans/2026-02-22-homelab-migration-impl.md << 'EOF'

---

## Migration Log

**Completed:** YYYY-MM-DD

- [ ] Config migrated from MacBook to arr-box
- [ ] TV shows migrated: NNN files, XXG
- [ ] Movies migrated: NNN files, XXG
- [ ] Jellyfin watch history confirmed
- [ ] All subdomain routes working (.local + .netbird.cloud)
- [ ] Android TV Jellyfin app connected to arr-box
- [ ] arr-stack autostart verified (reboot arr-box, confirm it comes back)
- [ ] MacBook arr-stack permanently stopped
EOF

git add docs/plans/2026-02-22-homelab-migration-impl.md
git commit -m "docs: migration complete — post-cutover verification log"
git push
```

---

## Reboot Test (Task 28)

**After everything is verified, reboot arr-box and confirm autostart:**

```bash
# On arr-box:
sudo reboot
```

Wait ~2 minutes, then from MacBook:

```bash
curl -s -o /dev/null -w "%{http_code}" http://arr-box.local
```

Expected: `200` — the stack came back up automatically, without any manual intervention.

This is the final success criterion: the family can watch TV with the MacBook shut down.
