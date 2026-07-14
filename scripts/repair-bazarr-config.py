#!/usr/bin/env python3
"""
Patch Bazarr config.yaml with current API keys and integration URLs.

Run on the arr-stack repo (or arr-box) after rotating keys, with .env.sops
or the equivalent environment variables sourced.

Sets:
- general.api_key -> BAZARR_API_KEY
- auth.apikey -> BAZARR_API_KEY (Bazarr UI/API basic-auth API key)
- sonarr.apikey -> SONARR_API_KEY
- sonarr.base_url -> http://gluetun:8989
- radarr.apikey -> RADARR_API_KEY
- radarr.base_url -> http://gluetun:7878
- general.movie_default_enabled -> true
- general.movie_default_profile -> 1  (Polish profile must exist in DB)
- general.serie_default_enabled -> true
- general.serie_default_profile -> 1  (Polish profile must exist in DB)

Preserves all other settings (providers, scores, languages, etc.).
"""

import os
import re
import sys
from pathlib import Path

CONFIG_PATH = Path(os.environ.get("BAZARR_CONFIG_PATH", "config/bazarr/config/config.yaml"))

REQUIRED = ["SONARR_API_KEY", "RADARR_API_KEY", "BAZARR_API_KEY"]


def redact(line: str) -> str:
    """Strip value after colon for any key-looking line."""
    if re.match(r"^\s*[a-z_]+:\s*[^\s]", line):
        return re.sub(r":\s*[^\s#].*$", ": ***", line)
    return line


def patch() -> None:
    missing = [k for k in REQUIRED if k not in os.environ]
    if missing:
        print(f"Missing env vars: {missing}", file=sys.stderr)
        print("Source .env.sops first, e.g.:", file=sys.stderr)
        print("SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d .env.sops > .env && set -a && source .env && set +a", file=sys.stderr)
        sys.exit(1)

    text = CONFIG_PATH.read_text()

    # API keys
    text = re.sub(
        r"^(sonarr:\n(?: .+\n)*  apikey: )[^\n]+",
        lambda m: f"{m.group(1)}{os.environ['SONARR_API_KEY']}",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^(radarr:\n(?: .+\n)*  apikey: )[^\n]+",
        lambda m: f"{m.group(1)}{os.environ['RADARR_API_KEY']}",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^(general:\n(?: .+\n)*  api_key: )[^\n]+",
        lambda m: f"{m.group(1)}{os.environ['BAZARR_API_KEY']}",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^(auth:\n(?: .+\n)*  apikey: )[^\n]+",
        lambda m: f"{m.group(1)}{os.environ['BAZARR_API_KEY']}",
        text,
        flags=re.MULTILINE,
    )

    # Integration base URL should be empty; Bazarr builds the URL from ip + port.
    # ip is set to 'gluetun' because Sonarr/Radarr use network_mode=service:gluetun
    # and gluetun publishes those service ports.
    text = re.sub(
        r"^(sonarr:\n(?: .+\n)*  base_url: )[^\n]*",
        lambda m: f"{m.group(1)}",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^(radarr:\n(?: .+\n)*  base_url: )[^\n]*",
        lambda m: f"{m.group(1)}",
        text,
        flags=re.MULTILINE,
    )

    # Default language profiles (Polish is profile ID 1)
    text = re.sub(
        r"^(general:\n(?: .+\n)*  movie_default_enabled: )[^\n]+",
        lambda m: f"{m.group(1)}true",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^(general:\n(?: .+\n)*  movie_default_profile: )[^\n]*",
        lambda m: f"{m.group(1)}1",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^(general:\n(?: .+\n)*  serie_default_enabled: )[^\n]+",
        lambda m: f"{m.group(1)}true",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^(general:\n(?: .+\n)*  serie_default_profile: )[^\n]*",
        lambda m: f"{m.group(1)}1",
        text,
        flags=re.MULTILINE,
    )

    CONFIG_PATH.write_text(text)

    print(f"Patched {CONFIG_PATH}")
    for line in CONFIG_PATH.read_text().splitlines():
        if any(k in line for k in ["apikey:", "api_key:", "base_url:", "movie_default_profile:", "serie_default_profile:", "movie_default_enabled:", "serie_default_enabled:"]):
            print("  " + redact(line))


if __name__ == "__main__":
    patch()
