"""
Collector - Load the Raw Data into the Staging Layer

Fetches planned timetables (/plan) and real-time changes (/fchg) for all stations and 
writes them into the tables defined in sql/01_staging.sql.
Meant to run regularly (e.g., hourly), because the API keeps no history.

Built on the earlier steps:
    fetch_samples.py        -> endpoints, auth, EVA numbers
    inspect_xml.py          -> which attributes exist, how often, what they look like
    01_staging.sql          -> target tables and primary keys
    docker-compose.yml      -> the database it writes to

Prerequisites: .env complete, database running, sql/01_staging.sql executed

Usage (from the repo root, venv active):
    python ingestion/collector.py
"""

import logging
import os
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import psycopg
import requests
from dotenv import load_dotenv

# --- CONFIGURATION ---

BASE_URL = "https://apis.deutschebahn.com/db-api-marketplace/apis/timetables/v1"

# The API expects date/hour in German local time
TZ = ZoneInfo("Europe/Berlin")

# Stations to collect: EVA number -> name (confirmed with fetch_samples.py)
STATIONS = {
    8000309: "Regensburg Hbf",
    8000261: "München Hbf",
    8000284: "Nürnberg Hbf",
    8002924: "Hof Hbf",
    8000217: "Landshut(Bay)Hbf",
    8000183: "Ingolstadt Hbf",
}

# How many hourly plan slices to fetch per run (current hour + next ones).
# Overlap between runs is fine: upserts prevent duplicates.
HOURS_AHEAD = 3

# Pause between requests to stay well below the 60 requests/minutes limit
REQUEST_PAUSE_SEC = 1.1

REQUEST_TIMEOUT_SEC = 30

log = logging.getLogger("collector")

# --- SQL STATEMENTS ---

# Upsert: insert new stops, refresh existing ones.
# first_seen_at keeps its original value, last_seen_at moves forward.
PLAN_UPSERT_SQL = """
INSERT INTO staging.stg_plan (
    eva, stop_id, station_name,
    trip_type, filter_flags, owner, category, trip_number,
    arr_pt, arr_pp, arr_line, arr_ppth,
    dep_pt, dep_pp, dep_line, dep_ppth,
    raw_xml
) VALUES (
    %(eva)s, %(stop_id)s, %(station_name)s,
    %(trip_type)s, %(filter_flags)s, %(owner)s, %(category)s, %(trip_number)s,
    %(arr_pt)s, %(arr_pp)s, %(arr_line)s, %(arr_ppth)s,
    %(dep_pt)s, %(dep_pp)s, %(dep_line)s, %(dep_ppth)s,
    %(raw_xml)s
)
ON CONFLICT (eva, stop_id) DO UPDATE SET
    station_name = EXCLUDED.station_name,
    trip_type    = EXCLUDED.trip_type,
    filter_flags = EXCLUDED.filter_flags,
    owner        = EXCLUDED.owner,
    category     = EXCLUDED.category,
    trip_number  = EXCLUDED.trip_number,
    arr_pt       = EXCLUDED.arr_pt,
    arr_pp       = EXCLUDED.arr_pp,
    arr_line     = EXCLUDED.arr_line,
    arr_ppth     = EXCLUDED.arr_ppth,
    dep_pt       = EXCLUDED.dep_pt,
    dep_pp       = EXCLUDED.dep_pp,
    dep_line     = EXCLUDED.dep_line,
    dep_ppth     = EXCLUDED.dep_ppth,
    raw_xml      = EXCLUDED.raw_xml,
    last_seen_at = now();
"""

CHANGES_UPSERT_SQL = """
INSERT INTO staging.stg_changes (
    eva, stop_id, station_name,
    category, trip_number,
    arr_ct, arr_cp, arr_cs, arr_clt, arr_line,
    dep_ct, dep_cp, dep_cs, dep_clt, dep_line,
    raw_xml
) VALUES (
    %(eva)s, %(stop_id)s, %(station_name)s,
    %(category)s, %(trip_number)s,
    %(arr_ct)s, %(arr_cp)s, %(arr_cs)s, %(arr_clt)s, %(arr_line)s,
    %(dep_ct)s, %(dep_cp)s, %(dep_cs)s, %(dep_clt)s, %(dep_line)s,
    %(raw_xml)s
)
ON CONFLICT (eva, stop_id) DO UPDATE SET
    station_name = EXCLUDED.station_name,
    category     = COALESCE(EXCLUDED.category, staging.stg_changes.category),
    trip_number  = COALESCE(EXCLUDED.trip_number, staging.stg_changes.trip_number),
    arr_ct       = EXCLUDED.arr_ct,
    arr_cp       = EXCLUDED.arr_cp,
    arr_cs       = EXCLUDED.arr_cs,
    arr_clt      = EXCLUDED.arr_clt,
    arr_line     = EXCLUDED.arr_line,
    dep_ct       = EXCLUDED.dep_ct,
    dep_cp       = EXCLUDED.dep_cp,
    dep_cs       = EXCLUDED.dep_cs,
    dep_clt      = EXCLUDED.dep_clt,
    dep_line     = EXCLUDED.dep_line,
    raw_xml      = EXCLUDED.raw_xml,
    last_seen_at = now();
"""

LOG_INSERT_SQL = """
INSERT INTO staging.ingestion_log (
    run_started_at, endpoint, eva, request_slot,
    http_status, rows_received, error_message
) VALUES (%s, %s, %s, %s, %s, %s, %s);
"""

# --- HELPERS ---

def load_config() -> dict:
    """Read credentials and DB settings from .env and stop early if something is missing."""
    load_dotenv()
    required = ["DB_CLIENT_ID", "DB_API_KEY", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB"]
    missing = [key for key in required if not os.getenv(key)]

    if missing:
        sys.exit(f"Missing values in .env: {', '.join(missing)}")

    return {
        "client_id": os.getenv("DB_CLIENT_ID"),
        "api_key": os.getenv("DB_API_KEY"),
        "db_conninfo": (
            f"host={os.getenv('POSTGRES_HOST', 'localhost')} "
            f"port={os.getenv('POSTGRES_PORT', '5432')} "
            f"dbname={os.getenv('POSTGRES_DB')} "
            f"user={os.getenv('POSTGRES_USER')} "
            f"password={os.getenv('POSTGRES_PASSWORD')}"
        ),
    }

def build_session(cfg: dict) -> requests.Session:
    """One HTTP session for all requests: reuses the connection and sets auth headers once."""
    session = requests.Session()
    session.headers.update({
        "DB-Client-Id": cfg["client_id"],
        "DB-Api-Key": cfg["api_key"],
        "Accept": "application/xml",
    })

    return session

def fetch(session: requests.Session, path: str) -> requests.Response:
    """GET request against the Timetables API, followed by a short pause (rate limit)."""
    try:
        return session.get(f"{BASE_URL}/{path}", timeout=REQUEST_TIMEOUT_SEC)
    finally:
        time.sleep(REQUEST_PAUSE_SEC)

def attr(element, name):
    """Safe attribute access: returns None if the element itself does not exist."""
    return element.get(name) if element is not None else None

def parse_timetable(xml_bytes: bytes, eva: int) -> tuple[str | None, list[dict]]:
    """
    Turn a <timetable> XML response into a list of flat dicts (one per <s> stop).
    Works for both /plan and /fchg responses; each upsert picks the keys it needs.
    """
    root = ET.fromstring(xml_bytes)
    station_name = root.get("station")
    rows = []

    for s in root.findall("s"):
        tl = s.find("tl")           # Trip label (category, number, operator)
        ar = s.find("ar")           # Arrival
        dp = s.find("dp")           # Departure

        rows.append({
            "eva": eva,
            "stop_id": s.get("id"),
            "station_name": station_name,

            # Trip label
            "trip_type": attr(tl, "t"),
            "filter_flags": attr(tl, "f"),
            "owner": attr(tl, "o"),
            "category": attr(tl, "c"),
            "trip_number": attr(tl, "n"),

            # Arrival: planned (p*) and changed (c*) values
            "arr_pt": attr(ar, "pt"),
            "arr_pp": attr(ar, "pp"),
            "arr_line": attr(ar, "l"),
            "arr_ppth": attr(ar, "ppth"),
            "arr_ct": attr(ar, "ct"),
            "arr_cp": attr(ar, "cp"),
            "arr_cs": attr(ar, "cs"),
            "arr_clt": attr(ar, "clt"),

            # Departure
            "dep_pt": attr(dp, "pt"),
            "dep_pp": attr(dp, "pp"),
            "dep_line": attr(dp, "l"),
            "dep_ppth": attr(dp, "ppth"),
            "dep_ct": attr(dp, "ct"),
            "dep_cp": attr(dp, "cp"),
            "dep_cs": attr(dp, "cs"),
            "dep_clt": attr(dp, "clt"),

            # Keep the complete element so no information is ever lost
            "raw_xml": ET.tostring(s, encoding="unicode"),
        })
 
    return station_name, rows

def explain_status(status: int) -> str:
    """Human-readable hints for the most common HTTP errors."""
    hints = {
        401: "credentials wrong (check DB_CLIENT_ID / DB_API_KEY in .env)",
        403: "application not subscribed to the Timetables API",
        404: "no data for this station/slot (or wrong EVA number)",
        410: "requested time slot is too far in the past/future",
        429: "rate limit reached, slow down",
    }

    return hints.get(status, "unexpected status")

# --- MODES ---

def run_collect(cfg: dict) -> None:
    """Normal run: fetch plan slices + changes for every station and upsert them."""
    session = build_session(cfg)
    run_started = datetime.now(TZ)
    log.info("Run started at %s", run_started.isoformat(timespec="seconds"))

    with psycopg.connect(cfg["db_conninfo"]) as conn:
        for eva, name in STATIONS.items():
            with conn.cursor() as cur:

                # 1. Planned timetable: current hour + HOURS_AHEAD - 1 following hours
                for offset in range(HOURS_AHEAD):
                    slot_time = run_started + timedelta(hours=offset)
                    slot = f"{slot_time:%y%m%d}/{slot_time:%H}"
                    collect_one(cur, session, run_started, "plan", eva,
                                f"plan/{eva}/{slot}", slot, PLAN_UPSERT_SQL)

                # 2. All known changes for this station
                collect_one(cur, session, run_started, "fchg", eva,
                            f"fchg/{eva}", None, CHANGES_UPSERT_SQL)

            # Commit per station: a later failure does not undo earlier stations
            conn.commit()
            log.info("Station %s (%s) done", eva, name)

    log.info("Run finished")

def collect_one(cur, session, run_started, endpoint, eva, path, slot, upsert_sql) -> None:
    """Fetch one endpoint, upsert its rows and write one ingestion_log entry."""
    status, n_rows, error = None, None, None

    try:
        resp = fetch(session, path)
        status = resp.status_code

        if status == 200:
            _, rows = parse_timetable(resp.content, eva)

            if rows:
                cur.executemany(upsert_sql, rows)
            n_rows = len(rows)
            log.info("  %-4s %s %-10s -> %d rows", endpoint, eva, slot or "", n_rows)

        else:
            error = explain_status(status)
            log.warning("  %-4s %s %-10s -> HTTP %s (%s)", endpoint, eva, slot or "", status, error)

    except (requests.RequestException, ET.ParseError) as exc:
        error = f"{type(exc).__name__}: {exc}"
        log.error("  %-4s %s failed: %s", endpoint, eva, error)

    cur.execute(LOG_INSERT_SQL, (run_started, endpoint, eva, slot, status, n_rows, error))

# --- ENTRY POINT ---

def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)-7s %(message)s")
    run_collect(load_config())

if __name__ == "__main__":
    main()