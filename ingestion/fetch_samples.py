"""
Fetch Samples - Look at the Raw Data

First contact with the DB Timetables API. Downloads raw API responses (/plan & /fchg) for all stations and saves them unchanged as XML files in samples/. 
Use these files to explore the raw data, e.g. with inspect_xml.py.

Prerequisite: .env with DB_CLIENT_ID and DB_API_KEY (from the DB API Marketplace).

Usage (from the repo root, venv active):
    python ingestion\fetch_samples.py --search Regensburg   # Find EVA numbers of a station
    python ingestion\fetch_samples.py                       # Save /plan + /fchg for all stations
"""

import argparse
import os
import re
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

import requests
from dotenv import load_dotenv

# --- CONFIGURATION ---

BASE_URL = "https://apis.deutschebahn.com/db-api-marketplace/apis/timetables/v1"

# The API expects date and hour in German local time
TZ = ZoneInfo("Europe/Berlin")
 
# Stations to sample: EVA number -> expected name.
# EVA numbers were looked up with --search, the API output confirms them.
STATIONS = {
    8000309: "Regensburg Hbf",
    8000261: "München Hbf",
    8000284: "Nürnberg Hbf",
    8002924: "Hof Hbf",
    8000217: "Landshut(Bay)Hbf",
    8000183: "Ingolstadt Hbf",
}
 
SAMPLES_DIR = Path("samples")

# Pause between requests to stay well below the rate limit (~60/minute).
REQUEST_PAUSE_SEC = 1.1

# Short explanations for the most common HTTP errors
STATUS_HINTS = {
    401: "credentials wrong (check DB_CLIENT_ID / DB_API_KEY in .env)",
    403: "application not subscribed to the Timetables API",
    404: "no data for this request (wrong EVA number or time slot?)",
    410: "time slot too far in the past or future",
    429: "rate limit reached, wait a moment",
}

# --- HTTP HELPERS ---

def create_session() -> requests.Session:
    """Read the API keys from .env and return a session that sends them with every request."""
    load_dotenv()
    client_id = os.getenv("DB_CLIENT_ID")
    api_key = os.getenv("DB_API_KEY")

    if not client_id or not api_key:
        sys.exit("DB_CLIENT_ID and DB_API_KEY must be set in .env")

    session = requests.Session()
    session.headers.update({
        "DB-Client-Id": client_id,
        "DB-Api-Key": api_key,
        "Accept": "application/xml",
    })
    return session

def get(session: requests.Session, path: str) -> requests.Response | None:
    """GET one endpoint, print a hint on errors, return the response only if it was successful."""
    response = session.get(f"{BASE_URL}/{path}", timeout = 30)      # Timeout: give up after 30s without a response instead of waiting forever.
    time.sleep(REQUEST_PAUSE_SEC)

    if response.status_code != 200:
        hint = STATUS_HINTS.get(response.status_code, "unexpected status")
        print(f"  {path} -> HTTP {response.status_code}: {hint}")
        return None
    
    return response

def save(response: requests.Response, filename: str) -> Path:
    """Write the raw response bytes to samples/<filename>: a 1:1 copy, nothing changed."""
    SAMPLES_DIR.mkdir(exist_ok = True)
    path = SAMPLES_DIR / filename
    path.write_bytes(response.content)

    return path

# --- MODES ---

def search_station(session: requests.Session, pattern: str) -> None:
    """Call /station/{pattern} and list all matches with their EVA number."""
    response = get(session, f"station/{quote(pattern)}")

    if response is None:
        return

    # File names not contain characters like * or umlauts
    safe_name = re.sub(r"[^A-Za-z0-9]+", "_", pattern)
    path = save(response, f"station_{safe_name}.xml")
 
    root = ET.fromstring(response.content)
    matches = root.findall(".//station")
    print(f"{len(matches)} match(es) for '{pattern}'  (raw response: {path})")

    for station in matches:
        print(f"  EVA {station.get('eva')}  {station.get('name')}")

def fetch_samples(session: requests.Session, hour: int | None) -> None:
    """Save one /plan and one /fchg response per station."""
    now = datetime.now(TZ)
    date = f"{now:%y%m%d}"          # e.g. 261020
    hour = now.hour if hour is None else hour

    for eva, expected_name in STATIONS.items():
        print(f"{eva}  {expected_name}")

        # 1. Planned timetable for one hour (static, contains no delays)
        response = get(session, f"plan/{eva}/{date}/{hour:02d}")

        if response is not None:
            path = save(response, f"plan_{eva}_{date}_{hour:02d}.xml")
            root = ET.fromstring(response.content)

            # Check if the EVA number belongs to the expected station.
            print(f"  plan  -> {path}  API says '{root.get('station')}', "
                  f"{len(root.findall('s'))} stops")

        # 2. All currently known changes (the minute is part of the file name because the content changes constantly).
        response = get(session, f"fchg/{eva}")

        if response is not None:
            path = save(response, f"fchg_{eva}_{now:%y%m%d_%H%M}.xml")
            root = ET.fromstring(response.content)
            print(f"  fchg  -> {path}  {len(root.findall('s'))} stops with changes")

        print(f"\nNext: python ingestion\\inspect_xml.py {SAMPLES_DIR}\\*.xml")
 
 
def main() -> None:
    parser = argparse.ArgumentParser(description="Download raw DB Timetables responses")
    parser.add_argument("--search", metavar="NAME", help="search a station and show its EVA number")
    parser.add_argument("--hour", type=int, help="hour 0-23 for /plan (default: current hour)")
    args = parser.parse_args()
 
    session = create_session()
    if args.search:
        search_station(session, args.search)
    else:
        fetch_samples(session, args.hour)
 
 
if __name__ == "__main__":
    main()