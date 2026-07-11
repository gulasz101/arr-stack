# Agent API Cookbook for arr-stack

> **For a weaker model:** every section below has a concrete, copy-pasteable example. Replace `YOUR_*` values with the real ones from `.env.sops`. Do not commit this file with real values filled in.

## Quick start: one command to test everything

After decrypting `.env.sops`, run this health check. It only reads status endpoints.

```bash
# Load secrets into the current shell from a temporary decrypted env file
set -a
source /tmp/arr-env-plain
set +a

# Health check every service
curl -s -o /dev/null -w "Sonarr:     %{http_code}\n" \
  "http://192.168.1.162:8989/api/v3/system/status?apikey=${SONARR_API_KEY}"
curl -s -o /dev/null -w "Radarr:     %{http_code}\n" \
  "http://192.168.1.162:7878/api/v3/system/status?apikey=${RADARR_API_KEY}"
curl -s -o /dev/null -w "Prowlarr:   %{http_code}\n" \
  "http://192.168.1.162:9696/api/v1/system/status?apikey=${PROWLARR_API_KEY}"
curl -s -o /dev/null -w "Bazarr:     %{http_code}\n" \
  -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/system/status"
curl -s -o /dev/null -w "qBittorrent: %{http_code}\n" \
  -X POST -d "username=admin&password=${QBITTORRENT_PASSWORD}" \
  -c /tmp/qb-cookies.txt \
  "http://192.168.1.162:8080/api/v2/auth/login"
curl -s -o /dev/null -w "Jellyfin:   %{http_code}\n" \
  "http://192.168.1.162:8096/System/Info?api_key=${JELLYFIN_API_KEY}"
```

All should return `200` except qBittorrent login, which returns `204` on success.

---

## 1. Decrypting `.env.sops` safely

### 1.1 Print to stdout (safe, never saved)

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops -d --input-type dotenv --output-type dotenv \
  ~/Projects/arr-stack/.env.sops
```

### 1.2 Decrypt to a temp file and load it

```bash
# Decrypt
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops -d --input-type dotenv --output-type dotenv \
  ~/Projects/arr-stack/.env.sops > /tmp/arr-env-plain

# Load into current shell
set -a
source /tmp/arr-env-plain
set +a

# Use the variables, then delete the temp file
rm -f /tmp/arr-env-plain
```

### 1.3 Re-encrypt after editing secrets

```bash
cd ~/Projects/arr-stack
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops -e --input-type dotenv --output-type dotenv .env > .env.sops
```

**Rule:** never leave `/tmp/arr-env-plain` behind. Delete it as soon as the command finishes.

---

## 2. Sonarr API examples

Base URL: `http://192.168.1.162:8989/api/v3`
Auth: `X-Api-Key` header or `?apikey=` query param.

### 2.1 Get system status

```bash
curl -s -H "X-Api-Key: ${SONARR_API_KEY}" \
  "http://192.168.1.162:8989/api/v3/system/status" | jq
```

Expected:
```json
{
  "version": "4.0.19.2979",
  "appName": "Sonarr",
  "instanceName": "Sonarr"
}
```

### 2.2 List all series

```bash
curl -s -H "X-Api-Key: ${SONARR_API_KEY}" \
  "http://192.168.1.162:8989/api/v3/series" | jq '.[] | {id, title, status}'
```

### 2.3 Search for a series to add

```bash
curl -s -H "X-Api-Key: ${SONARR_API_KEY}" \
  "http://192.168.1.162:8989/api/v3/series/lookup?term=silo" | jq '.[] | {title, tvdbId, year}'
```

### 2.4 Trigger a series search (refresh + search)

```bash
# Refresh series metadata (replace ID with real seriesId)
SERIES_ID=123
curl -s -X POST -H "X-Api-Key: ${SONARR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"RefreshSeries\",\"seriesId\":${SERIES_ID}}" \
  "http://192.168.1.162:8989/api/v3/command"

# Search for missing episodes
curl -s -X POST -H "X-Api-Key: ${SONARR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"SeriesSearch\",\"seriesId\":${SERIES_ID}}" \
  "http://192.168.1.162:8989/api/v3/command"
```

### 2.5 Force a full RSS sync

```bash
curl -s -X POST -H "X-Api-Key: ${SONARR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"name":"RssSync"}' \
  "http://192.168.1.162:8989/api/v3/command"
```

---

## 3. Radarr API examples

Base URL: `http://192.168.1.162:7878/api/v3`
Auth: `X-Api-Key` header or `?apikey=` query param.
Radarr must use `AuthenticationMethod=External` in `config.xml`.

### 3.1 Get system status

```bash
curl -s -H "X-Api-Key: ${RADARR_API_KEY}" \
  "http://192.168.1.162:7878/api/v3/system/status" | jq
```

### 3.2 List all movies

```bash
curl -s -H "X-Api-Key: ${RADARR_API_KEY}" \
  "http://192.168.1.162:7878/api/v3/movie" | jq '.[] | {id, title, monitored, status}'
```

### 3.3 Search for a movie to add

```bash
curl -s -H "X-Api-Key: ${RADARR_API_KEY}" \
  "http://192.168.1.162:7878/api/v3/movie/lookup?term=the+family+plan" | jq '.[] | {title, tmdbId, year}'
```

### 3.4 Trigger a movie search

```bash
MOVIE_ID=26
curl -s -X POST -H "X-Api-Key: ${RADARR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"MoviesSearch\",\"movieIds\":[${MOVIE_ID}]}" \
  "http://192.168.1.162:7878/api/v3/command"
```

### 3.5 Refresh one movie's metadata

```bash
curl -s -X POST -H "X-Api-Key: ${RADARR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"RefreshMovie\",\"movieIds\":[${MOVIE_ID}]}" \
  "http://192.168.1.162:7878/api/v3/command"
```

---

## 4. Prowlarr API examples

Base URL: `http://192.168.1.162:9696/api/v1`
Auth: `X-Api-Key` header or `?apikey=` query param.

### 4.1 Get system status

```bash
curl -s -H "X-Api-Key: ${PROWLARR_API_KEY}" \
  "http://192.168.1.162:9696/api/v1/system/status" | jq
```

### 4.2 List indexers

```bash
curl -s -H "X-Api-Key: ${PROWLARR_API_KEY}" \
  "http://192.168.1.162:9696/api/v1/indexer" | jq '.[] | {id, name, enableRss, enableInteractiveSearch}'
```

### 4.3 Test an indexer

```bash
INDEXER_ID=1
curl -s -X POST -H "X-Api-Key: ${PROWLARR_API_KEY}" \
  "http://192.168.1.162:9696/api/v1/indexer/action/check?indexerIds=${INDEXER_ID}" | jq
```

### 4.4 Add a tag (write test)

```bash
curl -s -X POST -H "X-Api-Key: ${PROWLARR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"label":"agent-test"}' \
  "http://192.168.1.162:9696/api/v1/tag" | jq
```

Response:
```json
{
  "id": 2,
  "label": "agent-test"
}
```

### 4.5 Delete the tag we just created

```bash
TAG_ID=2
curl -s -X DELETE -H "X-Api-Key: ${PROWLARR_API_KEY}" \
  "http://192.168.1.162:9696/api/v1/tag/${TAG_ID}"
```

---

## 5. Bazarr API examples

Base URL: `http://192.168.1.162:6767/api`
Auth: `X-API-KEY` header **only**. Query-param auth does **not** work.
Swagger: `http://192.168.1.162:6767/swagger.json`.

### 5.1 Get system status

```bash
curl -s -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/system/status" | jq
```

### 5.2 List language profiles

```bash
curl -s -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/system/languages/profiles" | jq '.[] | {profileId, name, code2}'
```

Expected:
```json
{
  "profileId": 1,
  "name": "Polish",
  "code2": "pl"
}
```

### 5.3 List movies with their language profile

```bash
curl -s -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/movies?start=0&length=500" | jq '.data[] | {radarrId, title, profileId}'
```

### 5.4 Assign the Polish profile to one movie

```bash
RADARR_ID=26
PROFILE_ID=1
curl -s -X POST -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/movies?radarrid=${RADARR_ID}&profileid=${PROFILE_ID}"

# Success is HTTP 204 with an empty body.
```

### 5.5 Assign Polish profile to all movies missing one

```bash
# Get all movies and assign profileId=1 (Polish) where profileId is null
movies_json=$(curl -s -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/movies?start=0&length=500")

echo "$movies_json" | jq -r '.data[] | select(.profileId == null) | .radarrId' | \
while read radarr_id; do
  curl -s -X POST -H "X-API-KEY: ${BAZARR_API_KEY}" \
    "http://192.168.1.162:6767/api/movies?radarrid=${radarr_id}&profileid=1"
  echo "assigned Polish to radarrId=${radarr_id}"
done
```

### 5.6 Search subtitles for all wanted movies

```bash
curl -s -X PATCH -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/movies?action=search-wanted"

# Success is HTTP 204.
```

### 5.7 List existing subtitles for a movie

```bash
RADARR_ID=26
curl -s -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/movies/subtitles?radarrid=${RADARR_ID}" | jq
```

Expected Polish subtitle:
```json
{
  "name": "Polish",
  "code2": "pl",
  "path": "/movies/The Family Plan (2023)/The Family Plan (2023) ... .pl.srt"
}
```

### 5.8 Same workflow for TV series

```bash
# List series
series_json=$(curl -s -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/series?start=0&length=500")

# Assign Polish profile where missing
echo "$series_json" | jq -r '.data[] | select(.profileId == null) | .sonarrSeriesId' | \
while read sonarr_id; do
  curl -s -X POST -H "X-API-KEY: ${BAZARR_API_KEY}" \
    "http://192.168.1.162:6767/api/series?sonarrseriesid=${sonarr_id}&profileid=1"
  echo "assigned Polish to sonarrSeriesId=${sonarr_id}"
done

# Search wanted episodes
curl -s -X PATCH -H "X-API-KEY: ${BAZARR_API_KEY}" \
  "http://192.168.1.162:6767/api/episodes?action=search-wanted"
```

---

## 6. qBittorrent API examples

WebUI: `http://192.168.1.162:8080`
Auth: WebUI username/password. LAN subnet is whitelisted.

### 6.1 Log in and save cookie

```bash
curl -s -X POST -c /tmp/qb-cookies.txt \
  -d "username=admin&password=${QBITTORRENT_PASSWORD}" \
  "http://192.168.1.162:8080/api/v2/auth/login"

# Success prints: Ok.
# Failure prints: Fails.
```

### 6.2 Check if already logged in

```bash
curl -s "http://192.168.1.162:8080/api/v2/auth/login" -b /tmp/qb-cookies.txt
```

### 6.3 List torrents

```bash
curl -s -b /tmp/qb-cookies.txt \
  "http://192.168.1.162:8080/api/v2/torrents/info" | jq '.[] | {name, hash, state, progress}'
```

### 6.4 Add a magnet link

```bash
MAGNET="magnet:?xt=urn:btih:..."
curl -s -X POST -b /tmp/qb-cookies.txt \
  -d "urls=${MAGNET}" \
  "http://192.168.1.162:8080/api/v2/torrents/add"
```

### 6.5 Pause and resume a torrent

```bash
HASH="abc123..."

# Pause
curl -s -X POST -b /tmp/qb-cookies.txt \
  -d "hashes=${HASH}" \
  "http://192.168.1.162:8080/api/v2/torrents/pause"

# Resume
curl -s -X POST -b /tmp/qb-cookies.txt \
  -d "hashes=${HASH}" \
  "http://192.168.1.162:8080/api/v2/torrents/resume"
```

### 6.6 Get global transfer speed

```bash
curl -s -b /tmp/qb-cookies.txt \
  "http://192.168.1.162:8080/api/v2/transfer/info" | jq '{dl_info_speed, up_info_speed}'
```

### 6.7 Log out when done

```bash
curl -s -X POST -b /tmp/qb-cookies.txt \
  "http://192.168.1.162:8080/api/v2/auth/logout"
rm -f /tmp/qb-cookies.txt
```

---

## 7. Jellyfin API examples

Base URL: `http://192.168.1.162:8096`
Auth: `api_key` query param.
**Do not rotate the Jellyfin API key without explicit approval.**

### 7.1 Get server info

```bash
curl -s "http://192.168.1.162:8096/System/Info?api_key=${JELLYFIN_API_KEY}" | jq '{ServerName, Version, LocalAddress}'
```

### 7.2 List users

```bash
curl -s "http://192.168.1.162:8096/Users?api_key=${JELLYFIN_API_KEY}" | jq '.[] | {Id, Name, LastActivityDate}'
```

### 7.3 Scan the media library

```bash
curl -s -X POST "http://192.168.1.162:8096/Library/Refresh?api_key=${JELLYFIN_API_KEY}"
```

### 7.4 Search for a movie

```bash
curl -s "http://192.168.1.162:8096/Items?api_key=${JELLYFIN_API_KEY}&SearchTerm=family+plan&IncludeItemTypes=Movie&Limit=5" | jq '.Items[] | {Name, Id, ProductionYear}'
```

---

## 8. Deployment and file-management recipes

### 8.1 Check that all containers are running

```bash
ssh arr-box "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"
```

### 8.2 Read container logs

```bash
ssh arr-box "docker logs --tail 50 gluetun"
ssh arr-box "docker logs --tail 50 sonarr"
```

### 8.3 Edit a config file owned by arrbox (UID 1100)

Example: change Radarr's auth method in `config.xml`.

```bash
# 1. Read the file from arr-box into a local temp file
ssh arr-box "docker run --rm -v /opt/arr-stack/config/radarr:/cfg alpine cat /cfg/config.xml" > /tmp/radarr-config.xml

# 2. Edit locally
sed -i 's/<AuthenticationMethod>Forms<\/AuthenticationMethod>/<AuthenticationMethod>External<\/AuthenticationMethod>/' /tmp/radarr-config.xml

# 3. Write it back with correct ownership
cat /tmp/radarr-config.xml | ssh arr-box "cat > /tmp/radarr-config.xml.new"
ssh arr-box "docker run --rm -v /opt/arr-stack/config/radarr:/cfg -v /tmp/radarr-config.xml.new:/tmp/new.xml:ro alpine sh -c 'cp /tmp/new.xml /cfg/config.xml && chown 1100:1100 /cfg/config.xml'"
rm -f /tmp/radarr-config.xml /tmp/radarr-config.xml.new
```

### 8.4 Back up all runtime configs before big changes

```bash
BACKUP_DIR="/opt/arr-stack/config-backups-$(date +%Y%m%d%H%M)"
ssh arr-box "
  docker run --rm -v /opt/arr-stack:/host alpine \
    sh -c 'mkdir -p /host/config-backups && cp -a /host/config/sonarr /host/config/radarr /host/config/prowlarr /host/config/bazarr /host/config/qbittorrent /host/config/jellyfin /host/config-backups/$(date +%Y%m%d%H%M) && chown -R 1100:1100 /host/config-backups/$(date +%Y%m%d%H%M)'
  echo backup at ${BACKUP_DIR}
"
```

### 8.5 Recreate the whole stack after a compose change

```bash
ssh arr-box "
  cd /opt/arr-stack
  docker compose pull
  docker compose up -d --force-recreate
"
```

---

## 9. What each service does (one-liners)

| Service | Port | Role |
|---|---|---|
| Caddy | 80 / 443 | Reverse proxy / HTTPS termination for Homepage and Jellyfin |
| Homepage | 3000 | Dashboard showing service health and quick links |
| Jellyfin | 8096 | Media server (clients, apps, web player) |
| Sonarr | 8989 | TV series management: search, download, organize |
| Radarr | 7878 | Movie management: search, download, organize |
| Prowlarr | 9696 | Indexer manager shared by Sonarr/Radarr |
| Bazarr | 6767 | Subtitle search and download for Sonarr/Radarr |
| qBittorrent | 8080 | BitTorrent client running behind the VPN |
| Gluetun | 8888 / others | VPN client (Mullvad) carrying qBittorrent, Sonarr, Radarr, Prowlarr, FlareSolverr |
| FlareSolverr | 8191 | Cloudflare challenge solver for some indexers |

---

## 10. Cross-service API keys and URLs (silent killers)

After rotating credentials, update **both ends** of every connection. The worst failures are silent: Bazarr loses its nav, Radarr reports "0 active indexers".

### 10.1 Why `localhost` is wrong

Sonarr, Radarr, Prowlarr, qBittorrent, and FlareSolverr use `network_mode: service:gluetun`. Inside that namespace `localhost` is gluetun, not the sibling container. Cross-service URLs must use `http://gluetun:<port>/`.

| Stored in | Points to | Required host | Required key |
|---|---|---|---|
| Sonarr indexers (`radarr.db` `Indexers`) | Prowlarr | `gluetun:9696` | `PROWLARR_API_KEY` |
| Radarr indexers (`sonarr.db` `Indexers`) | Prowlarr | `gluetun:9696` | `PROWLARR_API_KEY` |
| Prowlarr Sonarr app (`prowlarr.db` `Applications`) | Sonarr | `gluetun:8989` | `SONARR_API_KEY` |
| Prowlarr Radarr app (`prowlarr.db` `Applications`) | Radarr | `gluetun:7878` | `RADARR_API_KEY` |
| Bazarr `config.yaml` `sonarr.*` | Sonarr | `gluetun:8989` | `SONARR_API_KEY`, `enabled: true` |
| Bazarr `config.yaml` `radarr.*` | Radarr | `gluetun:7878` | `RADARR_API_KEY`, `enabled: true` |

### 10.2 Automated repair

Repo script: `scripts/repair-cross-api-keys.py`.

```bash
# 1. Decrypt .env.sops
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops -d --input-type dotenv --output-type dotenv \
  ~/Projects/arr-stack/.env.sops > /tmp/arr-env-plain
set -a
source /tmp/arr-env-plain
set +a
rm -f /tmp/arr-env-plain

# 2. Backup the three DBs
TS=$(date +%Y%m%d%H%M)
ssh arr-box "mkdir -p /opt/arr-stack/config-backups-$TS && \
  cp /opt/arr-stack/config/sonarr/sonarr.db \
     /opt/arr-stack/config/radarr/radarr.db \
     /opt/arr-stack/config/prowlarr/prowlarr.db \
     /opt/arr-stack/config-backups-$TS/"

# 3. Run the repair
scp ~/Projects/arr-stack/scripts/repair-cross-api-keys.py arr-box:/tmp/repair-cross-api-keys.py
ssh arr-box "docker run --rm \
  -v /tmp/repair-cross-api-keys.py:/script.py:ro \
  -v /opt/arr-stack/config:/opt/arr-stack/config \
  -e SONARR_API_KEY=$SONARR_API_KEY \
  -e RADARR_API_KEY=$RADARR_API_KEY \
  -e PROWLARR_API_KEY=$PROWLARR_API_KEY \
  alpine sh -c 'apk add -q python3 && python3 /script.py'"

# 4. Restart the three containers
ssh arr-box "docker restart sonarr radarr prowlarr"
```

### 10.3 Manual Bazarr enable

If Bazarr only shows **Settings** in the left nav, the integrations are disabled. Use the web UI:

1. `http://192.168.1.162:6767/settings/sonarr` → enable, host `gluetun`, port `8989`, key `SONARR_API_KEY`, Test, Save.
2. `http://192.168.1.162:6767/settings/radarr` → enable, host `gluetun`, port `7878`, key `RADARR_API_KEY`, Save.

Navigation reappears immediately.

### 10.4 Verify indexer search works

```bash
# Find a Radarr movie id
MOVIE_ID=$(curl -s -H "X-Api-Key: ${RADARR_API_KEY}" \
  "http://192.168.1.162:7878/api/v3/movie" | jq -r '.[0].id')

# Search
COUNT=$(curl -s -H "X-Api-Key: ${RADARR_API_KEY}" \
  "http://192.168.1.162:7878/api/v3/release?movieId=${MOVIE_ID}" | jq length)
echo "Radarr found $COUNT releases for movie $MOVIE_ID"
```

A number greater than 0 means indexers are healthy.

---

## 11. Troubleshooting quick reference

| Symptom | First thing to check |
|---|---|
| No service responds | `ssh arr-box "docker ps"` — is the container up? |
| VPN-side services down (qBit, Sonarr, Radarr, Prowlarr, FlareSolverr) | `docker logs gluetun` and exit IP |
| Bazarr 401/405 | Are you using `X-API-KEY` header? Query-param auth fails. |
| Bazarr only shows Settings | Sonarr/Radarr integrations disabled or unhealthy; fix keys and URLs, then enable in UI. |
| Radarr interactive search "No results found" | `0 active indexers` → check indexer baseUrl/key and Prowlarr app config. |
| Radarr redirects to login | `AuthenticationMethod` in `config.xml` must be `External` |
| qBittorrent says `Ok.` but next call fails | Did you use `-c` to save the cookie and `-b` to send it? |
| File edit fails with permission denied | Use the Docker-root trick; `/opt/arr-stack` is owned by UID 1100. |
| `.env.sops` decrypt fails | Is `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt` exported? |

---

## 12. Safety checklist before any edit

1. Is the change reflected in the `gulasz101/arr-stack` repo first?
2. Are all credentials loaded from `.env.sops`, never typed into tracked files?
3. Did you delete any temp decrypted env files after use?
4. Did you back up `/opt/arr-stack/config/` before touching runtime configs?
5. Did you run a read + one safe write test after deploying?

If you answer **no** to any of these, stop and ask the Supreme Leader.
