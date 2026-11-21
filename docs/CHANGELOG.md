# Changelog

All changes to data collection, cleaning and preparation, newest first.
Format: version - date - what was added, changed, fixed or removed, and why.

---

## v1.3 - 2026-11-21 - Mart layer and dashboard

#### Added
- Mart layer in `sql/04_mart.sql` with four views: `mart.stations` (short names and coordinates), `mart.stops` (one row per stop, flags as 0/1), `mart.segments` (delay change between consecutive stations of one journey) and `mart.network` (stations and sections for the network map). The same rules as in the analysis apply, so the dashboard shows the same values as the SQL queries.
- CSV exports of three mart views in `exports/`, including the commands to re-create them. Tableau Public cannot connect to PostgreSQL.
- Query Q2b in `sql/03_analysis.sql`: least punctual lines across all six stations, as shown in the line scorecard of the dashboard.
- Interactive Tableau Public dashboard with two views (overview and time pattern), published.
- Share and Act sections of the case study.

#### Fixed
- `mart.network` showed a section München - Nürnberg that does not exist as a direct connection. Sections are now only shown if there are at least 20 journeys in each direction.
- Views in `sql/04_mart.sql` are dropped in reverse order of creation, so the script can be run again without dependency errors.

---

## v1.2 - 2026-11-15 - Trip ID fix

#### Fixed
- `trip_id` in `core.stops` now keeps the origin departure (`stop_id` without only the stop index). The first part of the stop ID repeats every day for the same train, so journeys of different days were merged into one trip. Found in the analysis (Q4 showed impossible segments such as "Regensburg → Regensburg"). Number of trips: 20,132 instead of 2,945.

#### Added
- Verification check: one journey passes each station at most once (result: 0 violations).
- Analysis queries for Q1-Q6 in `sql/03_analysis.sql`, including Q5b (cancellations at Hof by day).

---

## v1.1 - 2026-11-14 - Verification

#### Added
- `is_suspect_delay` flag in `core.stops`. Verification found 13 stops more than 10 min early; early departures, arrivals more than 30 min early and delays in the daylight saving night (25 Oct, 1-4 a.m.) are not credible. Rows are kept, flagged delays are excluded from delay metrics.

#### Fixed
- Docstrings in `fetch_samples.py` and `inspect_xml.py` are raw strings, so Windows paths are no longer read as escape characters.
- `fetch_samples.py` prints the "Next:" hint once instead of after every station.
- Typos in SQL comments.

---

## v1.0 - 2026-11-06 - Data frozen

#### Changed
- Data collection stopped. Final dataset: 20 Oct - 6 Nov 2026, 25,106 stops.
- Full database backup created with `pg_dump`.

---

## v0.4 - 2026-10-21 - Core layer

#### Added
- View `core.stops`: one clean row per stop with readable names, timestamps, actual times, delays, cancellation and on-time flags.
- `service_type` (long distance / regional / S-Bahn / bus), derived from the train category.

#### Changed
- `line` falls back to category + number (e.g. `ICE 1003`). Verification showed that long-distance trains have no line in the API (351 stops without a line).

---

## v0.3 - 2026-10-21 - Automation and station fix

#### Added
- Hourly collection with Windows Task Scheduler (`run_collector.bat`), with a log file per run.
- Ingolstadt Hbf (8000183) as sixth station.

---

## v0.2 - 2026-10-20 - Collection and staging

#### Added
- Raw samples and field inventory (`fetch_samples.py`, `inspect_xml.py`) before designing tables.
- Staging tables `stg_plan`, `stg_changes`, `ingestion_log`; collector loading `/plan` and `/fchg` with upsert.

#### Fixed
- Regensburg was first queried under EVA 8089430, which turned out to be the rail replacement bus stop. Changed to 8000309 (Regensburg Hbf).

---

## v0.1 - 2026-10-19 - Setup

#### Added
- Repository, PostgreSQL 17 in Docker, Python environment.


