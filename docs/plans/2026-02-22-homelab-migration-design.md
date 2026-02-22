# Arr-Stack Homelab Migration — Design Document

**Date:** 2026-02-22
**Author:** Wojciech Gula
**Status:** Approved

---

## Overview

The goal of this migration is to move the arr-stack (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Bazarr, FlareSolverr, Homepage, Caddy, Gluetun) from a MacBook Pro to a dedicated homelab setup. The driving reason: the MacBook must remain on for the family to watch media via Jellyfin on an Android TV box — an unacceptable constraint for a laptop.

The homelab consists of two machines:
- **openmediavault.local** — NAS for persistent storage
- **arr-box.local** — Debian 13 mini PC that will run the Docker Compose stack

After migration, the MacBook will no longer be required for media serving. The arr-box runs 24/7, serves media to the TV over the local network, and is also reachable via NetBird VPN from mobile devices.

---

## Current State (MacBook)

| Item | Value |
|---|---|
| Media path | `/Users/wojciechgula/Media` |
| TV shows | ~185 GB |
| Movies | ~54 GB |
| Downloads | ~109 GB (will NOT be migrated — only completed media moves) |
| Stack hostname | `wojciechs-macbook-pro.local` |
| PUID/PGID | 501 / 20 (macOS defaults) |

The `.env` file on the MacBook contains live Mullvad WireGuard credentials, API keys for all services, and path configuration. It is git-ignored and not committed to the repo.

---

## Target Architecture

```
MacBook (macOS)
  └── git push ──────────────────► GitHub (private repo)
                                        │
                                        │ git pull + just deploy
                                        ▼
                              arr-box.local (Debian 13)
                              arr-box.netbird.cloud
                                   │
                                   │  Docker Compose stack
                                   │  Systemd autostart
                                   │  NFS mounts from OMV
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                             ▼
             /mnt/media                    /mnt/downloads
        (NFS → OMV 3.7T disk)          (NFS → OMV 1.4T disk)
                    │
         openmediavault.local
           ├── /srv/3.7T/media/{tv,movies}
           └── /srv/1.4T/downloads
           └── Copyparty (permanent, port 3923, password-protected)
```

### Access Paths

| Client | URL | What opens |
|---|---|---|
| TV (local network) | `http://arr-box.local` | Homepage dashboard |
| Phone (NetBird VPN) | `http://arr-box.netbird.cloud` | Homepage dashboard |
| TV → Jellyfin | `http://jellyfin.arr-box.local` | Jellyfin |
| Phone → Jellyfin | `http://jellyfin.arr-box.netbird.cloud` | Jellyfin |
| TV → Sonarr | `http://sonarr.arr-box.local` | Sonarr |
| TV → Radarr | `http://radarr.arr-box.local` | Radarr |
| TV → Prowlarr | `http://prowlarr.arr-box.local` | Prowlarr |
| TV → qBittorrent | `http://qbit.arr-box.local` | qBittorrent WebUI |
| TV → Bazarr | `http://bazarr.arr-box.local` | Bazarr |

All subdomain variants also work with `.netbird.cloud` suffix.

---

## Component Design

### 1. OpenMediaVault (openmediavault.local)

**Disks:**
- `/dev/sda` (3.7T) → media storage: `/srv/dev-disk-.../media/tv` and `.../media/movies`
- `/dev/sdd` (1.4T) → downloads: `/srv/dev-disk-.../downloads`

**Dedicated service user:**
```
username: arrbox
UID:      1100
GID:      1100
purpose:  owns all arr-stack files on OMV; same UID used inside Docker containers
```

The `arrbox` user is OMV-specific and has read/write access only to the arr-stack shares. Future users for other devices get separate shares with no overlap.

**NFS exports (configured via OMV web UI):**

| Export path | Client | Options |
|---|---|---|
| `/srv/.../media` | arr-box IP only | `rw,sync,no_root_squash,no_subtree_check` |
| `/srv/.../downloads` | arr-box IP only | `rw,sync,no_root_squash,no_subtree_check` |

**Copyparty (permanent service):**
- Installed via `pip` as the `arrbox` user
- Runs as a systemd service: `copyparty.service`
- Port: `3923`
- Password-protected (admin user)
- Serves `/srv/.../media` read/write during migration; kept running permanently for future uploads
- Access: `http://openmediavault.local:3923`

### 2. arr-box (arr-box.local / arr-box.netbird.cloud)

**System user:**
```
username: arrbox
UID:      1100
GID:      1100
purpose:  runs Docker daemon (via rootless) or is the PUID/PGID for containers
```

**Software installed:**
- Docker Engine + Docker Compose plugin (via apt)
- `just` (task runner)
- `age` (encryption tool)
- `sops` (secrets manager)
- `nfs-common` (NFS client)

**NFS mounts in `/etc/fstab`:**
```
openmediavault.local:/srv/.../media     /mnt/media      nfs  defaults,_netdev,uid=1100,gid=1100  0 0
openmediavault.local:/srv/.../downloads /mnt/downloads  nfs  defaults,_netdev,uid=1100,gid=1100  0 0
```

**App directory:**
```
/opt/arr-stack/
  ├── docker-compose.yml
  ├── .env.sops         ← encrypted secrets (committed to git)
  ├── .env              ← decrypted at runtime (git-ignored)
  ├── .sops.yaml        ← SOPS config (age recipient)
  ├── justfile          ← deployment commands
  ├── config/           ← service configs (as before)
  └── docs/plans/       ← this file and implementation plans
```

**justfile commands:**
```makefile
# Decrypt .env.sops → .env
decrypt:
    sops -d .env.sops > .env

# Full deploy: decrypt then start stack
deploy: decrypt
    docker compose up -d

# Update: pull new images and redeploy
update: decrypt
    docker compose pull && docker compose up -d

# Show live logs
logs:
    docker compose logs -f

# Stop the stack
stop:
    docker compose down

# Status
status:
    docker compose ps
```

**Systemd autostart (`/etc/systemd/system/arr-stack.service`):**
```ini
[Unit]
Description=Arr Stack Media Server
After=network-online.target remote-fs.target
Requires=remote-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/arr-stack
ExecStartPre=/usr/bin/just decrypt
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=arrbox

[Install]
WantedBy=multi-user.target
```

### 3. Docker Compose Changes

Changes from the current MacBook `docker-compose.yml`:

**Environment variables:**
- `PUID=1100` / `PGID=1100` — matches the `arrbox` user
- `MEDIA_PATH=/mnt/media` — NFS mount
- `DOWNLOAD_PATH=/mnt/downloads` — NFS mount

**Caddy — dual hostname routing:**

The Caddyfile will be updated to handle two base hostnames simultaneously:
```caddyfile
{
    auto_https off
}

# Shared routing snippet
(arr-routes) {
    @dashboard path /
    handle @dashboard {
        reverse_proxy homepage:3000
    }
}

# Local network access
http://arr-box.local {
    reverse_proxy homepage:3000
}
http://jellyfin.arr-box.local {
    reverse_proxy jellyfin:8096
}
http://sonarr.arr-box.local {
    reverse_proxy gluetun:8989
}
# ... (radarr, prowlarr, qbit, bazarr)

# NetBird VPN access (identical routes, different domain)
http://arr-box.netbird.cloud {
    reverse_proxy homepage:3000
}
http://jellyfin.arr-box.netbird.cloud {
    reverse_proxy jellyfin:8096
}
# ... (same pattern)
```

The environment variable `ARR_HOSTNAME` will be replaced by two variables:
- `ARR_HOSTNAME_LOCAL=arr-box.local`
- `ARR_HOSTNAME_NETBIRD=arr-box.netbird.cloud`

**Homepage — updated service URLs:**

`services.yaml` URLs change from `localhost:PORT` to container service names:
- `http://gluetun:8989` for Sonarr/Radarr/Prowlarr (behind VPN container)
- `http://jellyfin:8096` for Jellyfin
- `http://bazarr:6767` for Bazarr
- `http://homepage:3000` → already internal

`HOMEPAGE_ALLOWED_HOSTS` will include both hostnames:
```
arr-box.local,arr-box.netbird.cloud,localhost
```

### 4. Secrets Management (SOPS + age)

**Setup (one-time on MacBook):**
```bash
# Generate age key pair
age-keygen -o ~/.config/sops/age/keys.txt
# → outputs: public key  age1xxxx...

# Store private key in 1Password: vault "Homelab", item "arr-stack age key"

# Configure .sops.yaml
cat .sops.yaml:
  creation_rules:
    - path_regex: .env
      age: age1xxxx...  # public key

# Encrypt existing .env
sops -e .env > .env.sops
```

**Deployment on arr-box (one-time):**
```bash
# Retrieve age private key from 1Password
# Install to: ~/.config/sops/age/keys.txt

# Deploy
just deploy
```

**Git workflow for secret changes:**
```bash
# Edit encrypted secrets
sops .env.sops        # opens decrypted in $EDITOR, re-encrypts on save

# Commit
git add .env.sops
git commit -m "secrets: update Mullvad WireGuard key"
git push

# On arr-box: pull and redeploy
git pull && just deploy
```

The `.env` file remains in `.gitignore`. Only `.env.sops` (encrypted) is committed.

---

## Media Migration Plan

### Tools
- **Copyparty** installed on both MacBook and OMV
- Uses parallel chunked HTTP uploads for LAN-saturating throughput
- Generates SHA-512 checksums for integrity verification

### Phases

**Phase 0 — Prep (OMV):**
- Install copyparty on OMV as `arrbox` user
- Start copyparty server pointing at `/srv/.../media`
- Verify accessible from MacBook: `curl http://openmediavault.local:3923`

**Phase 1 — Migrate TV shows (~185G):**
```bash
# On MacBook:
copyparty-client upload \
  --url http://openmediavault.local:3923 \
  --auth user:password \
  --threads 8 \
  /Users/wojciechgula/Media/tv
```

**Phase 2 — Migrate Movies (~54G):**
```bash
copyparty-client upload \
  --url http://openmediavault.local:3923 \
  --auth user:password \
  --threads 8 \
  /Users/wojciechgula/Media/movies
```

**Phase 3 — Verify integrity:**
- Copyparty provides a built-in file browser with checksum comparison
- Spot-check counts: number of files, total size on both ends

**Phase 4 — Cutover:**
1. Stop arr-stack on MacBook: `docker compose down`
2. Confirm arr-stack is running on arr-box: `just status`
3. Open `http://arr-box.local` — verify Homepage dashboard loads
4. Open `http://jellyfin.arr-box.local` — verify library scan completes
5. Test Jellyfin from Android TV box
6. Confirm Sonarr/Radarr watching history is intact (config migrated via `config/` dirs)

**Not migrated:** Downloads folder (~109G). Active/seeding torrents do not move; Sonarr/Radarr will re-queue anything incomplete if needed.

---

## GitOps Commit Strategy

Every infrastructure change will be a separate, descriptive commit. Planned commit sequence:

1. `docs: add homelab migration design document`
2. `chore: add docs/plans directory structure`
3. `sops: add .sops.yaml and initial .env.sops encryption`
4. `feat: add justfile for deployment commands`
5. `feat(caddy): update Caddyfile for arr-box.local and arr-box.netbird.cloud`
6. `feat(compose): update docker-compose for arr-box (PUID 1100, NFS paths)`
7. `feat(homepage): update service URLs and allowed hosts for arr-box`
8. `feat(systemd): add arr-stack.service autostart unit`
9. `docs: add OMV setup instructions`
10. `docs: add arr-box setup instructions`
11. `docs: document copyparty migration procedure`
12. `docs: migration complete — post-cutover verification`

---

## Success Criteria

- [ ] arr-stack starts automatically on arr-box boot (no manual intervention)
- [ ] `http://arr-box.local` opens Homepage dashboard on the local network
- [ ] `http://arr-box.netbird.cloud` opens Homepage dashboard over NetBird
- [ ] `http://jellyfin.arr-box.local` works from Android TV Jellyfin app
- [ ] `http://jellyfin.arr-box.netbird.cloud` works from mobile over VPN
- [ ] All subdomain services reachable on both `.local` and `.netbird.cloud`
- [ ] Jellyfin watch history migrated (users, progress, libraries)
- [ ] All TV shows and movies accessible in Jellyfin after migration
- [ ] `.env.sops` committed to git; no plaintext secrets in repo
- [ ] age private key stored in 1Password under "Homelab" vault
- [ ] MacBook arr-stack stopped; MacBook not required for family TV viewing
- [ ] Copyparty running permanently on OMV for future transfers

---

## Out of Scope

- Migrating the downloads folder (~109G of in-progress/seeded torrents)
- Setting up HTTPS/TLS on the local network (not needed for home use)
- Configuring other OMV users/shares beyond `arrbox` for arr-stack
- Any changes to the existing Sonarr/Radarr/Prowlarr indexer configuration
- Automated CI/CD (GitHub Actions deployment)

---

## Risk Notes

- **NFS mount failure at boot** — mitigated by `After=remote-fs.target` + `Requires=remote-fs.target` in the systemd unit; stack won't start until NFS is ready
- **NetBird subdomain routing** — requires NetBird's Magic DNS to resolve `*.arr-box.netbird.cloud`; if wildcard doesn't work, explicit DNS entries may be needed in NetBird admin
- **Jellyfin metadata** — the `config/jellyfin/` directory contains the database, metadata cache, and user watch history; this must be transferred intact
- **Gluetun VPN on Linux** — needs `/dev/net/tun` device and `NET_ADMIN` capability; standard on Debian with Docker but requires verification
