#!/usr/bin/env python3
"""
Update cross-service API keys in arr-stack runtime SQLite databases.

Run on arr-box after rotating API keys, with .env.sops decrypted.
Updates:
- Sonarr indexers (Prowlarr Torznab) -> new PROWLARR_API_KEY
- Radarr indexers (Prowlarr Torznab) -> new PROWLARR_API_KEY
- Prowlarr Applications (Sonarr/Radarr apps) -> new SONARR_API_KEY / RADARR_API_KEY
"""
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

CONFIG_ROOT = Path("/opt/arr-stack/config")

SONARR_KEY = os.environ["SONARR_API_KEY"]
RADARR_KEY = os.environ["RADARR_API_KEY"]
PROWLARR_KEY = os.environ["PROWLARR_API_KEY"]


def fix_localhost_to_gluetun(settings: dict) -> bool:
    """Because Sonarr/Radarr/Prowlarr use network_mode=service:gluetun, localhost inside
    those containers is gluetun itself. Cross-service URLs must use gluetun as host."""
    changed = False
    for key in ("baseUrl", "prowlarrUrl"):
        if key in settings and isinstance(settings[key], str):
            new_url = re.sub(r"https?://localhost:(\d+)", r"http://gluetun:\1", settings[key])
            if new_url != settings[key]:
                print(f"    fixed {key}: {settings[key]} -> {new_url}")
                settings[key] = new_url
                changed = True
    return changed


def update_sonarr_indexers():
    db_path = CONFIG_ROOT / "sonarr" / "sonarr.db"
    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()
    cur.execute("SELECT Id, Name, Settings FROM Indexers WHERE Implementation = 'Torznab'")
    rows = cur.fetchall()
    for row_id, name, settings_json in rows:
        settings = json.loads(settings_json)
        changed = False
        old_key = settings.get("apiKey")
        if old_key and old_key != PROWLARR_KEY:
            settings["apiKey"] = PROWLARR_KEY
            changed = True
            print(f"[sonarr] {name} apiKey: {old_key[:8]}... -> {PROWLARR_KEY[:8]}...")
        if fix_localhost_to_gluetun(settings):
            changed = True
            print(f"[sonarr] {name} baseUrl -> gluetun")
        if changed:
            cur.execute(
                "UPDATE Indexers SET Settings = ? WHERE Id = ?",
                (json.dumps(settings), row_id),
            )
    conn.commit()
    conn.close()


def update_radarr_indexers():
    db_path = CONFIG_ROOT / "radarr" / "radarr.db"
    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()
    cur.execute("SELECT Id, Name, Settings FROM Indexers WHERE Implementation = 'Torznab'")
    rows = cur.fetchall()
    for row_id, name, settings_json in rows:
        settings = json.loads(settings_json)
        changed = False
        old_key = settings.get("apiKey")
        if old_key and old_key != PROWLARR_KEY:
            settings["apiKey"] = PROWLARR_KEY
            changed = True
            print(f"[radarr] {name} apiKey: {old_key[:8]}... -> {PROWLARR_KEY[:8]}...")
        if fix_localhost_to_gluetun(settings):
            changed = True
            print(f"[radarr] {name} baseUrl -> gluetun")
        if changed:
            cur.execute(
                "UPDATE Indexers SET Settings = ? WHERE Id = ?",
                (json.dumps(settings), row_id),
            )
    conn.commit()
    conn.close()


def update_prowlarr_apps():
    db_path = CONFIG_ROOT / "prowlarr" / "prowlarr.db"
    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()
    cur.execute("SELECT Id, Name, Settings FROM Applications")
    rows = cur.fetchall()
    for row_id, name, settings_json in rows:
        settings = json.loads(settings_json)
        changed = False
        old_key = settings.get("apiKey")
        new_key = SONARR_KEY if name == "Sonarr" else RADARR_KEY if name == "Radarr" else None
        if new_key and old_key and old_key != new_key:
            settings["apiKey"] = new_key
            changed = True
            print(f"[prowlarr] {name} apiKey: {old_key[:8]}... -> {new_key[:8]}...")
        if fix_localhost_to_gluetun(settings):
            changed = True
            print(f"[prowlarr] {name} baseUrl -> gluetun")
        if changed:
            cur.execute(
                "UPDATE Applications SET Settings = ? WHERE Id = ?",
                (json.dumps(settings), row_id),
            )
    conn.commit()
    conn.close()


if __name__ == "__main__":
    if "SONARR_API_KEY" not in os.environ:
        print("Source .env.sops first: SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d .env.sops > .env && set -a && source .env && set +a")
        sys.exit(1)

    update_sonarr_indexers()
    update_radarr_indexers()
    update_prowlarr_apps()
    print("Done. Restart sonarr, radarr, and prowlarr containers.")
