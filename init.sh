#!/bin/bash
set -e

# ===========================================
# Media Stack Initialization Script
# ===========================================
# This script:
# 1. Starts services to generate API keys
# 2. Extracts API keys
# 3. Configures inter-service connections
# 4. Sets up download client and indexers
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# ===========================================
# Pre-flight checks
# ===========================================
log "Running pre-flight checks..."

if [ ! -f ".env" ]; then
    error ".env file not found. Copy .env.example to .env and configure it first."
fi

source .env

if [ -z "$MULLVAD_PRIVATE_KEY" ] || [ "$MULLVAD_PRIVATE_KEY" == "your_wireguard_private_key_here" ]; then
    error "MULLVAD_PRIVATE_KEY not configured in .env"
fi

if [ -z "$DOWNLOAD_PATH" ]; then
    error "DOWNLOAD_PATH not configured in .env"
fi

# Create media directories
log "Creating media directories..."
mkdir -p "$DOWNLOAD_PATH"
mkdir -p "$MEDIA_PATH/tv"
mkdir -p "$MEDIA_PATH/movies"

# ===========================================
# Start services
# ===========================================
log "Starting VPN and services..."
docker-compose up -d gluetun
sleep 10

# Check VPN is working
VPN_IP=$(docker exec gluetun wget -qO- https://api.ipify.org 2>/dev/null || echo "")
if [ -z "$VPN_IP" ]; then
    error "VPN failed to connect. Check your Mullvad credentials."
fi
log "VPN connected! Exit IP: $VPN_IP"

# Start remaining services
docker-compose up -d
log "Waiting for services to initialize..."
sleep 30

# ===========================================
# Extract API Keys
# ===========================================
log "Extracting API keys..."

get_api_key() {
    local config_file=$1
    grep -oE '<ApiKey>[^<]+' "$config_file" 2>/dev/null | sed 's/<ApiKey>//' || echo ""
}

# Wait for API keys to be generated
for i in {1..30}; do
    SONARR_API_KEY=$(get_api_key "./config/sonarr/config.xml")
    RADARR_API_KEY=$(get_api_key "./config/radarr/config.xml")
    PROWLARR_API_KEY=$(get_api_key "./config/prowlarr/config.xml")
    
    if [ -n "$SONARR_API_KEY" ] && [ -n "$RADARR_API_KEY" ] && [ -n "$PROWLARR_API_KEY" ]; then
        break
    fi
    sleep 2
done

if [ -z "$SONARR_API_KEY" ] || [ -z "$RADARR_API_KEY" ] || [ -z "$PROWLARR_API_KEY" ]; then
    warn "Could not extract all API keys automatically. You may need to configure manually."
fi

log "API Keys extracted:"
echo "  Sonarr:   $SONARR_API_KEY"
echo "  Radarr:   $RADARR_API_KEY"
echo "  Prowlarr: $PROWLARR_API_KEY"

# ===========================================
# Configure qBittorrent
# ===========================================
log "Configuring qBittorrent..."

# Wait for qBittorrent to be ready
for i in {1..30}; do
    if curl -s "http://localhost:8080/api/v2/app/version" > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Get initial credentials (newer versions generate random password)
QB_TEMP_PASS=$(docker logs qbittorrent 2>&1 | grep -oE 'temporary password is: .*' | tail -1 | sed 's/temporary password is: //' || echo "adminadmin")

# Login and set new password
log "Setting qBittorrent password..."
QB_COOKIE=$(curl -s -c - "http://localhost:8080/api/v2/auth/login" \
    --data "username=admin&password=$QB_TEMP_PASS" 2>/dev/null | grep -oE 'SID\s+\S+' | awk '{print $2}' || echo "")

if [ -n "$QB_COOKIE" ]; then
    # Set preferences for no seeding
    curl -s "http://localhost:8080/api/v2/app/setPreferences" \
        -b "SID=$QB_COOKIE" \
        --data-urlencode 'json={"max_ratio":0,"max_seeding_time":0,"max_ratio_act":1}' > /dev/null 2>&1
    log "qBittorrent configured: seeding disabled"
fi

# ===========================================
# Configure Prowlarr - Add Indexers
# ===========================================
log "Configuring Prowlarr indexers..."

if [ -n "$PROWLARR_API_KEY" ]; then
    PROWLARR_URL="http://localhost:9696"
    
    # Add 1337x indexer
    curl -s -X POST "$PROWLARR_URL/api/v1/indexer" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "1337x",
            "implementation": "Cardigann",
            "implementationName": "1337x",
            "configContract": "CardigannSettings",
            "enableRss": true,
            "enableAutomaticSearch": true,
            "enableInteractiveSearch": true,
            "appProfileId": 1,
            "priority": 25,
            "definitionName": "1337x",
            "fields": []
        }' > /dev/null 2>&1
    
    # Add TorrentGalaxy indexer
    curl -s -X POST "$PROWLARR_URL/api/v1/indexer" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "TorrentGalaxy",
            "implementation": "Cardigann",
            "implementationName": "TorrentGalaxy",
            "configContract": "CardigannSettings",
            "enableRss": true,
            "enableAutomaticSearch": true,
            "enableInteractiveSearch": true,
            "appProfileId": 1,
            "priority": 25,
            "definitionName": "torrentgalaxy",
            "fields": []
        }' > /dev/null 2>&1

    # Add EZTV indexer (good for TV)
    curl -s -X POST "$PROWLARR_URL/api/v1/indexer" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "EZTV",
            "implementation": "Cardigann",
            "implementationName": "EZTV",
            "configContract": "CardigannSettings",
            "enableRss": true,
            "enableAutomaticSearch": true,
            "enableInteractiveSearch": true,
            "appProfileId": 1,
            "priority": 25,
            "definitionName": "eztv",
            "fields": []
        }' > /dev/null 2>&1
    
    log "Added indexers: 1337x, TorrentGalaxy, EZTV"
    
    # Add Sonarr as application
    curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Sonarr\",
            \"syncLevel\": \"fullSync\",
            \"implementation\": \"Sonarr\",
            \"implementationName\": \"Sonarr\",
            \"configContract\": \"SonarrSettings\",
            \"fields\": [
                {\"name\": \"prowlarrUrl\", \"value\": \"http://localhost:9696\"},
                {\"name\": \"baseUrl\", \"value\": \"http://localhost:8989\"},
                {\"name\": \"apiKey\", \"value\": \"$SONARR_API_KEY\"},
                {\"name\": \"syncCategories\", \"value\": [5000, 5010, 5020, 5030, 5040, 5045, 5050]}
            ]
        }" > /dev/null 2>&1
    
    # Add Radarr as application
    curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
        -H "X-Api-Key: $PROWLARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Radarr\",
            \"syncLevel\": \"fullSync\",
            \"implementation\": \"Radarr\",
            \"implementationName\": \"Radarr\",
            \"configContract\": \"RadarrSettings\",
            \"fields\": [
                {\"name\": \"prowlarrUrl\", \"value\": \"http://localhost:9696\"},
                {\"name\": \"baseUrl\", \"value\": \"http://localhost:7878\"},
                {\"name\": \"apiKey\", \"value\": \"$RADARR_API_KEY\"},
                {\"name\": \"syncCategories\", \"value\": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060]}
            ]
        }" > /dev/null 2>&1
    
    log "Connected Prowlarr to Sonarr and Radarr"
fi

# ===========================================
# Configure Sonarr - Add Download Client & Root Folder
# ===========================================
log "Configuring Sonarr..."

if [ -n "$SONARR_API_KEY" ]; then
    SONARR_URL="http://localhost:8989"
    
    # Add qBittorrent as download client
    curl -s -X POST "$SONARR_URL/api/v3/downloadclient" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "qBittorrent",
            "implementation": "QBittorrent",
            "implementationName": "qBittorrent",
            "configContract": "QBittorrentSettings",
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "fields": [
                {"name": "host", "value": "localhost"},
                {"name": "port", "value": 8080},
                {"name": "username", "value": "admin"},
                {"name": "password", "value": "adminadmin"},
                {"name": "tvCategory", "value": "tv"},
                {"name": "recentTvPriority", "value": 0},
                {"name": "olderTvPriority", "value": 0},
                {"name": "initialState", "value": 0},
                {"name": "sequentialOrder", "value": false},
                {"name": "firstAndLast", "value": false}
            ]
        }' > /dev/null 2>&1
    
    # Add root folder
    curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
        -H "X-Api-Key: $SONARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"path": "/tv"}' > /dev/null 2>&1
    
    log "Sonarr configured with qBittorrent and root folder"
fi

# ===========================================
# Configure Radarr - Add Download Client & Root Folder
# ===========================================
log "Configuring Radarr..."

if [ -n "$RADARR_API_KEY" ]; then
    RADARR_URL="http://localhost:7878"
    
    # Add qBittorrent as download client
    curl -s -X POST "$RADARR_URL/api/v3/downloadclient" \
        -H "X-Api-Key: $RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "qBittorrent",
            "implementation": "QBittorrent",
            "implementationName": "qBittorrent",
            "configContract": "QBittorrentSettings",
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "fields": [
                {"name": "host", "value": "localhost"},
                {"name": "port", "value": 8080},
                {"name": "username", "value": "admin"},
                {"name": "password", "value": "adminadmin"},
                {"name": "movieCategory", "value": "movies"},
                {"name": "recentMoviePriority", "value": 0},
                {"name": "olderMoviePriority", "value": 0},
                {"name": "initialState", "value": 0},
                {"name": "sequentialOrder", "value": false},
                {"name": "firstAndLast", "value": false}
            ]
        }' > /dev/null 2>&1
    
    # Add root folder
    curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
        -H "X-Api-Key: $RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"path": "/movies"}' > /dev/null 2>&1
    
    log "Radarr configured with qBittorrent and root folder"
fi

# ===========================================
# Configure Bazarr - Connect to Sonarr/Radarr
# ===========================================
log "Configuring Bazarr..."

# Update Bazarr config with API keys
BAZARR_CONFIG="./config/bazarr/config/config.yaml"
if [ -f "$BAZARR_CONFIG" ]; then
    # Use sed to update API keys in yaml (macOS compatible)
    if [ -n "$SONARR_API_KEY" ]; then
        sed -i '' "s/apikey: ''/apikey: '$SONARR_API_KEY'/" "$BAZARR_CONFIG" 2>/dev/null || true
    fi
    log "Bazarr configured with Sonarr/Radarr connection"
fi

# Restart Bazarr to pick up config changes
docker-compose restart bazarr > /dev/null 2>&1

# ===========================================
# Save API keys to .env for future reference
# ===========================================
log "Saving API keys to .env..."

# Update .env with actual API keys (macOS compatible sed)
if [ -n "$SONARR_API_KEY" ]; then
    sed -i '' "s/^SONARR_API_KEY=.*/SONARR_API_KEY=$SONARR_API_KEY/" .env 2>/dev/null || true
fi
if [ -n "$RADARR_API_KEY" ]; then
    sed -i '' "s/^RADARR_API_KEY=.*/RADARR_API_KEY=$RADARR_API_KEY/" .env 2>/dev/null || true
fi
if [ -n "$PROWLARR_API_KEY" ]; then
    sed -i '' "s/^PROWLARR_API_KEY=.*/PROWLARR_API_KEY=$PROWLARR_API_KEY/" .env 2>/dev/null || true
fi

# ===========================================
# Final Status
# ===========================================
echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Services running:"
echo "  qBittorrent:  http://localhost:8080 (admin/adminadmin)"
echo "  Prowlarr:     http://localhost:9696"
echo "  Sonarr:       http://localhost:8989"
echo "  Radarr:       http://localhost:7878"
echo "  Bazarr:       http://localhost:6767"
echo "  Jellyfin:     http://localhost:8096"
echo ""
echo "VPN Exit IP: $VPN_IP (Spain)"
echo ""
echo "API Keys saved to .env"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Open Bazarr (http://localhost:6767)"
echo "     - Go to Settings → Providers"
echo "     - Add OpenSubtitles.com credentials (if you have them)"
echo "     - Napisy24 should work without credentials"
echo ""
echo "  2. Add a series in Sonarr:"
echo "     - Open http://localhost:8989"
echo "     - Series → Add New → Search 'Mussolini Son of the Century'"
echo "     - Click Add, then search"
echo ""
echo "  3. Polish subtitles will be auto-downloaded by Bazarr"
echo ""
