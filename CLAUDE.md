# Agent Operating Instructions for arr-stack / arr-box

## What this is

The arr-stack is the Supreme Leader's home media server: Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, Gluetun (Mullvad VPN), Homepage, FlareSolverr, and Caddy. It runs on a dedicated LAN machine `arr-box.local` (`192.168.1.162`) with Docker Compose. Media and downloads live on OpenMediaVault NFS shares.

Everything is meant to be GitOps-driven from `https://github.com/gulasz101/arr-stack`. Runtime secrets are encrypted in `.env.sops` with SOPS+age.

## How to access arr-box

- SSH as `gulasz101@arr-box.local` using `~/.ssh/id_ed25519.homelab-2nd`.
- `gulasz101` is in the `docker` group. That is **root-equivalent** for container and most file operations on `/opt/arr-stack`.
- **DO NOT hard-code, print, or commit the sudo password.** For the rare command that truly needs `sudo`, ask the Supreme Leader via a secure channel or fetch it from the password manager.
- The project directory on the host is `/opt/arr-stack`. It is owned by the `arrbox` service user (UID 1100), so file operations usually require the Docker-root trick (see below).

## Decrypting secrets

Use the age private key at `~/.config/sops/age/keys.txt`:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops -d --input-type dotenv --output-type dotenv \
  ~/Projects/arr-stack/.env.sops
```

For deployment, decrypt to a temporary file and clean it up immediately. Never commit plaintext.

## Deploying changes

The Supreme Leader prefers every runtime change reflected in the repo first. The normal flow is:

1. Edit `docker-compose.yml`, `CLAUDE.md`, or other tracked files in `~/Projects/arr-stack`.
2. If rotating secrets, edit the decrypted `.env`, re-encrypt to `.env.sops`, and commit.
3. Push to `origin main`.
4. Copy the updated files to arr-box and recreate the stack.

Because `/opt/arr-stack` is owned by `arrbox`, use the Docker-root trick to place files:

```bash
# On Hermes host: send files over SSH to /tmp on arr-box
cat ~/Projects/arr-stack/.env.sops | ssh arr-box "cat > /tmp/arr-stack-env-sops"
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops -d --input-type dotenv --output-type dotenv \
  ~/Projects/arr-stack/.env.sops | ssh arr-box "cat > /tmp/arr-stack-env-plain"
cat ~/Projects/arr-stack/docker-compose.yml | ssh arr-box "cat > /tmp/arr-stack-docker-compose.yml"

# On arr-box: place files into /opt/arr-stack with correct ownership
ssh arr-box "
  docker run --rm -v /opt/arr-stack:/host -v /tmp/arr-stack-env-sops:/tmp/new.sops:ro alpine \
    sh -c 'cp /tmp/new.sops /host/.env.sops && chown 1100:1100 /host/.env.sops && chmod 664 /host/.env.sops'
  docker run --rm -v /opt/arr-stack:/host -v /tmp/arr-stack-env-plain:/tmp/new.env:ro alpine \
    sh -c 'cp /tmp/new.env /host/.env && chown 1100:1100 /host/.env && chmod 664 /host/.env'
  docker run --rm -v /opt/arr-stack:/host -v /tmp/arr-stack-docker-compose.yml:/tmp/new.yml:ro alpine \
    sh -c 'cp /tmp/new.yml /host/docker-compose.yml && chown 1100:1100 /host/docker-compose.yml'
  rm -f /tmp/arr-stack-env-sops /tmp/arr-stack-env-plain /tmp/arr-stack-docker-compose.yml
  cd /opt/arr-stack
  docker compose pull
  docker compose up -d --force-recreate
"
```

Clean up any decrypted files on the Hermes host immediately afterwards.

## Service API access from LAN

All services are reachable on `192.168.1.162`. Read credentials from `.env.sops`.

### Sonarr

- Base URL: `http://192.168.1.162:8989/api/v3`
- Auth: `X-Api-Key` header or `?apikey=` query param.
- Auth method in `config.xml`: `External`.

### Radarr

- Base URL: `http://192.168.1.162:7878/api/v3`
- Auth: `X-Api-Key` header or `?apikey=` query param.
- Auth method in `config.xml`: `External`.

### Prowlarr

- Base URL: `http://192.168.1.162:9696/api/v1`
- Auth: `X-Api-Key` header or `?apikey=` query param.
- Auth method in `config.xml`: `External`.

### Bazarr

- Base URL: `http://192.168.1.162:6767/api`
- Auth: `X-API-KEY` header only (NOT query param).
- Swagger UI: `http://192.168.1.162:6767/swagger.json`.
- Useful endpoints:
  - `GET /api/system/languages/profiles`
  - `GET /api/movies?start=0&length=500`
  - `POST /api/movies?radarrid=ID&profileid=1` — assign language profile
  - `PATCH /api/movies?action=search-wanted` — search for missing subtitles
  - Same pattern with `/api/series` and `sonarrSeriesId` for TV.

### qBittorrent

- WebUI: `http://192.168.1.162:8080`
- Login: `POST /api/v2/auth/login` with `username=admin&password=...`
- After login, the session cookie (`QBT_SID_8080`) is used for subsequent requests.
- LAN subnet whitelist is enabled; local calls do not need additional auth beyond the WebUI password.

### Jellyfin

- Base URL: `http://192.168.1.162:8096`
- Auth: `api_key` query param or `X-Emby-Authorization` header.
- **Do not rotate the Jellyfin API key without explicit approval** — it will force all clients/TVs to re-authenticate.

## Secrets rules

- The repo is public-bound. **Never commit plaintext credentials, tokens, passwords, or private keys.**
- All runtime credentials live in `.env.sops` encrypted with age.
- The age public key is in `.sops.yaml` in the repo.
- The age **private** key is at `~/.config/sops/age/keys.txt` on the Hermes host and in the Supreme Leader's password manager. It never enters the repo.
- If you are unsure whether a value is a secret, treat it as one and encrypt it or ask.

## Container image policy

- All images in `docker-compose.yml` are pinned to explicit semver/build tags. No `:latest`.
- When an image needs updating, look up the current stable tag on Docker Hub or GitHub releases, update `docker-compose.yml`, and recreate the stack.
- Consider adding a Renovate or Dependabot rule later to keep pinned tags current.

## Observability

- Homepage (`http://192.168.1.162:3000`) gives a quick service health dashboard.
- Individual service `/health` or `/ping` endpoints:
  - Bazarr: `GET /api/system/ping`
  - FlareSolverr: `GET /health`
  - Sonarr/Radarr/Prowlarr: `GET /api/v(3|1)/system/status`

## Common gotchas

1. **Gluetun must be healthy before VPN-side services work.** If services behind Gluetun are unreachable, check `docker logs gluetun` and the exit IP first.
2. **Bazarr takes ~1 minute to warm up** after a recreate; early curls may time out even though the container is `Up`.
3. **Bazarr API uses `X-API-KEY` header, not `?apikey=`.** Query-param auth will fail confusingly.
4. **Radarr must be `External` auth for agent access.** If API calls return a login redirect, check `AuthenticationMethod` in `config.xml`.
5. **Never rewrite arr-box history with force-push unless explicitly told to.** The local `/opt/arr-stack` repo is owned by `arrbox`; coordinate file placement carefully.

## What to do if credentials leak

If any credential is printed in chat, written to a non-encrypted file, or committed plaintext:

1. **Rotate the credential immediately.**
2. **If it hit the git repo, scrub it from history** with `git-filter-repo` and force-push. This was already done once for the arr-box sudo password; do not let it happen again.
3. **Tell the Supreme Leader.**

## References

- Repo: `https://github.com/gulasz101/arr-stack`
- Host: `arr-box.local` / `192.168.1.162`
- Project dir: `/opt/arr-stack`
- Secrets: `~/Projects/arr-stack/.env.sops`
- Age key: `~/.config/sops/age/keys.txt`
