# Data Dictionary - db-delay-dwh

Reference for the used data in this project: where each field comes from, what it means and how it is stored.
→ Companion to `docs/CASE_STUDY.md` (section 2 and 3).

---

## 1. Overview

```
DB Timetables API                     PostgreSQL (bahn_dwh)
─────────────────────────             ───────────────────────────────────────────
/plan/{eva}/{date}/{hour}   → XML →   staging.stg_plan        planned stops
/fchg/{eva}                 → XML →   staging.stg_changes     real-time changes
(collector run metadata)       →      staging.ingestion_log   one row per request

                                      → core.stops (view)     one clean row per stop
                                      → mart.* (views)        prepared for the dashboard
                                      → exports/*.csv         → Tableau Public
```

### Layer naming convention

| Layer | Column names | Data types | Purpose |
|---|---|---|---|
| staging | close to the source (`arr_pt`) | raw (mostly Text) | 1:1 copy of the API |
| core | readable (`planned_arrival_at`) | proper types (`TIMESTAMP`, `BOOLEAN`) | cleaned, joined, one truth |
| mart | short and business-friendly (`station`, `on_time`) | numeric 0/1 flags instead of `BOOLEAN` | ready for Tableau: AVG of a flag = share |

**Why staging keeps the cryptic names?** When a value looks wrong, you can compare the column directly with the API docs (arr_pt = <ar pt="...">). Readable names are introduced in the core layer, where the "suggested name" column is used.

---

## 2. Data source

| Item | Value |
|---|---|
| Provider| Deutsche Bahn, DB API Marketplace |
| API | Timetables v1 |
| Base URL | `https://apis.deutschebahn.com/db-api-marketplace/apis/timetables/v1` |
| Auth headers| `DB-Client-ID`, `DB-Api-Key` |
| Format | XML |
| Rate limit| free plan: 60 requests/minute |
| History | none (the API only returns the current day and the next hours) |
| Licence | CC BY 4.0, attribution: Deutsche Bahn AG |
| Full field reference | OpenAPI spec `Timetables-*.json` |

### Endpoints

| Endpoint | Returns | Target table | Called |
| `/station/{pattern}`| station search -> EVA number (= ID of German stations) | - (manual lookup) | once, by hand |
| `/plan/{evaNo}/{date}/{hour}`| planned stops for one hour (no delays) | `stg_plan` | every run (current hour +2) |
| `/fchg/{evaNo}`| all known changes for the station (delay, platform changes, cancellations) | `stg_changes` | every run |
| `/rchg/{evaNo}`| only changes from the last ~2 minutes | - | - |

### Stations collected

| EVA | Station | Note |
|---|---|---|
| 8000309 | Regensburg Hbf | main station of the project |
| 8000261 | München Hbf |  |
| 8000284 | Nürnberg Hbf |  |
| 8000183 | Hof Hbf |  |
| 8000217 | Landshut(Bay)Hbf |  |
| 8089430 | Regensburg Hauptbahnhof (bus stop) | rail replacement buses (not collected) |

## 3. XML structure

One response = one `<timetable>`, with many `<s>`(stop) elements.

```xml
<timetable station="Regensburg Hbf">                       <!-- station name -->
  <s id="-3396501293033557189-2610191340-8">               <!-- one stop of one train -->
    <tl f="N" t="p" o="8007H3" c="RE" n="4860"/>            <!-- trip label: which train -->
    <ar pt="2610191512" pp="4" l="RE2" ppth="München..."/>  <!-- arrival (optional) -->
    <dp pt="2610191520" pp="4" l="RE2" ppth="Schwandorf..."/> <!-- departure (optional) -->
  </s>
</timetable>
```

| Element | Meaning | Always present? |
|---|---|---|
| `<timetable>` | response root, carries the station name | yes |
| `<s>` | one train stopping at this station | yes (0..n per response) |
| `<tl>` | trip label: category, number, operator | in `/plan` yes, in `/fchg` rarely |
| `<ar>` | arrival event | no: missing if the train starts here |
| `<dp>` | departure event | no: missing if the train ends here |
| `<m>` | message (e.g. delay reason), child of `<s>`, `<ar>` or `<dp>` | only in `/fchg`, sometimes |

### Time format

All times are text in the format `yyMMddHHmm`, in German local time without time zone.

2610191512 → 2026-10-19 15:12

SQL conversion: to_timestamp('2610191512', 'YYMMDDHH24MI')::timestamp

### The stop ID

```
-3396501293033557189 - 2610191340 - 8
└──────── trip id ───┘ └ origin ─┘  └ stop index
                        departure     (position of this station on the route,
                        at first      1 = train starts here)
                        station
```

The trip id can start with a minus, so the ID is split from the end: the last two parts are origin departure and stop index, the rest is the trip id.

---

## 4. staging.stg_plan

Source: /plan
Grain: one row per stop of one train at one station
Primary key: `(eva, stop_id)`
Write mode: upsert (new stops inserted, known stops updated)

| Column | Source (XML) | Meaning | Example | Type |
|---|---|---|---|---|
| `eva` | request parameter | station ID | `8000309` | Integer |
| `stop_id` | `s@id` | ID of this stop event | `-3396…-2610191340-8` | Text |
| `station_name` | `timetable@station` | station name from the API | `Regensburg Hbf` | Text |
| `trip_type` | `tl@t` | trip type (always `p` in the data) | `p` | Text |
| `filter_flags` | `tl@f` | service class flag | `N`, `D` | Text |
| `owner` | `tl@o` | operator code | `8007H3` | Text |
| `category` | `tl@c` | train category | `RE`, `ICE`, `ag`, `S`, `Bus` | Text |
| `trip_number` | `tl@n` | train number | `4860` | Text |
| `arr_pt` | `ar@pt` | planned arrival time | `2610191512` | Text |
| `arr_pp` | `ar@pp` | planned arrival platform | `4`, `8 D-F` | Text |
| `arr_line` | `ar@l` | line | `RE2` | Text |
| `arr_ppth` | `ar@ppth` | planned route before this station, `\|`-separated | `München Hbf\|Freising\|…` | Text |
| `dep_pt` | `dp@pt` | planned departure time | `2610191520` | Text |
| `dep_pp` | `dp@pp` | planned departure platform | `4` | Text |
| `dep_line` | `dp@l` | line | `RE2` | Text |
| `dep_ppth` | `dp@ppth` | planned route after this station | `Schwandorf\|Weiden…` | Text |
| `raw_xml` | whole `<s>` element | original data, safety net | `<s id=…>…</s>` | Text |
| `first_seen_at` | database | first time the stop was fetched | | TIMESTAMPTZ |
| `last_seen_at` | database | last time the stop was fetched | | TIMESTAMPTZ |

| `<ar>` | `<dp>` | Meaning |
|---|---|---|
| Met | Met | train passes through |
| Met | - | train ends here |
| - | Met | train starts here (stop index 1) |

---

## 5. staging.stg_changes

Source: /fchg
Grain: one row per stop with real-time data
Primary key: `(eva, stop_id)`
Write mode: upsert (only the latest known state is kept)
Joins to: `stg_plan` on `(eva, stop_id)`

| Column | Source (XML) | Meaning | Example | Type |
|---|---|---|---|---|
| `eva` | request parameter | station ID | `8000309` | Integer |
| `stop_id` | `s@id` | same ID as in `stg_plan` | | Text |
| `station_name` | `timetable@station` | station name | | Text |
| `category` / `trip_number` | `tl@c` / `tl@n` | only for added trips | | Text |
| `arr_ct` / `dep_ct` | `ar@ct` / `dp@ct` | changed (expected or actual) time | `2610191519` | Text |
| `arr_cp` / `dep_cp` | `ar@cp` / `dp@cp` | changed platform | `5` | Text |
| `arr_cs` / `dep_cs` | `ar@cs` / `dp@cs` | status: `p` planned, `a` added, `c` cancelled | `c` | Text |
| `arr_clt` / `dep_clt` | `ar@clt` / `dp@clt` | time of cancellation | | Text |
| `arr_line` / `dep_line` | `ar@l` / `dp@l` | line | `RE50` | Text |
| `raw_xml` | whole `<s>` element | original, includes `<m>` messages | | Text |
| `first_seen_at` / `last_seen_at` | database | first / last time a change was fetched | | TIMESTAMPTZ |

Note: `/fchg` reports a changed time for almost every stop of the coming hours, including on-time ones (`ct = pt`). 97.3 % of all planned stops have a row here. A stop without a row is therefore more likely "not captured" than "on time".

Limitation: only the latest state is stored. The delay is the last value seen, up to one hour before the train passed.

---

## 6. staging.ingestion_log

Source: written by `collector.py`
Grain: one row per API request
Primary key: `log_id`

| Column | Meaning | Example | Type |
|---|---|---|---|
| `log_id` | auto-increment ID | `42` | BIGSERIAL |
| `run_started_at` | start of the collector run (same for all requests of one run) | | TIMESTAMPTZ |
| `endpoint` | `plan` or `fchg` | `plan` | Text |
| `eva` | requested station | `8000309` | Integer |
| `request_slot` | `yyMMdd/HH` for plan, empty for fchg | `261020/16` | Text |
| `http_status` | HTTP response code, empty if no response | `200` | Integer |
| `rows_received` | number of `<s>` elements | `17` | Integer |
| `error_message` | error description | | Text |
| `logged_at` | time the row was written | | TIMESTAMPTZ |

---

## 7. core.stops (view)

Source: `sql/02_core.sql` 
Built from: `stg_plan` LEFT JOIN `stg_changes`
Grain: one row per stop of one train at one station
Key: `(station_eva, stop_id)`
Rows: 25,106

| Column | Type | Meaning | Derived from |
|---|---|---|---|
| `station_eva` | Integer | station ID | `eva` |
| `station_name` | Text | station name | `station_name` |
| `stop_id` | Text | ID of this stop event | `stop_id` |
| `trip_id` | Text | ID of one journey on one day (same at all stations of that journey) | `stop_id` without the stop index |
| `trip_started_at` | TIMESTAMP | departure at the origin station | middle part of `stop_id` |
| `stop_index` | Integer | position of the station on the route (1 = origin) | last part of `stop_id` |
| `service_type` | Text | `long distance` / `regional` / `S-Bahn` / `bus` | `train_category` |
| `train_category` | Text | ICE, RE, ag, S, Bus … | `category` |
| `train_number` | Text | train number | `trip_number` |
| `line` | Text | line; for long-distance trains category + number, e.g. `ICE 1003` | `arr_line`, `dep_line`, fallback |
| `origin_station` | Text | first station of the trip | first element of `arr_ppth` |
| `destination_station` | Text | last station of the trip | last element of `dep_ppth` |
| `service_date` | Date | operating day | date of `planned_event_at` |
| `planned_event_at` | TIMESTAMP | planned departure, or arrival if the train ends here | |
| `planned_arrival_at` / `actual_arrival_at` | TIMESTAMP | arrival planned / actual | `arr_pt` / `arr_ct`, else planned |
| `planned_departure_at` / `actual_departure_at` | TIMESTAMP | departure planned / actual | `dep_pt` / `dep_ct`, else planned |
| `planned_platform` / `actual_platform` | Text | platform planned / actual | `pp` / `cp` |
| `is_platform_changed` | Boolean | actual platform differs from planned | |
| `arrival_delay_min` / `departure_delay_min` | Integer | delay in minutes; empty if cancelled | actual − planned |
| `delay_min` | Integer | arrival delay, or departure delay if the train starts here | |
| `is_on_time` | Boolean | less than 6 minutes late; empty if cancelled | |
| `delay_category` | Text | `cancelled`, `early`, `on time`, `delayed 6-15`, `delayed 16-60`, `delayed > 60` | |
| `is_suspect_delay` | Boolean | delay not credible: early departure, arrival > 30 min early, DST change night | see CHANGELOG v1.1 |
| `arrival_status` / `departure_status` | Text | `p` planned, `a` added, `c` cancelled | `cs` |
| `is_origin` / `is_terminus` | Boolean | train starts / ends here | no arrival / no departure |
| `is_rail_replacement` | Boolean | bus instead of train | `train_category = 'Bus'` |
| `is_cancelled` | Boolean | arrival or departure cancelled | status `c` |
| `has_change_record` | Boolean | real-time data exists for this stop | |
| `change_last_seen_at` | TIMESTAMPTZ | last update of the real-time data | `stg_changes.last_seen_at` |

### Service types

| Service type | Categories |
|---|---|
| long distance | ICE, IC, EC, ECE, RJ, RJX, EN, NJ, WB, FLX, TGV |
| S-Bahn | S |
| bus | Bus |
| regional | all others (RE, RB, ag, ARV, ALX, BRB, OPB, MRB, EB, VBG …) |

---

## 8. Mart layer (views for the dashboard)

Built by `sql/04_mart.sql` on top of `core.stops`. The same rules as in the analysis apply: stops with `is_suspect_delay` are left out. Flags are stored as 0/1, so that AVG and SUM work directly in Tableau. Three views are exported as CSV files to `exports/`, because Tableau Public cannot connect to PostgreSQL.

| View | Grain | Rows | Export |
|---|---|---|---|
| `mart.stations` | one row per station | 6 | none (lookup, joined into the other views) |
| `mart.stops` | one row per stop | 25,088 | `exports/stops.csv` |
| `mart.segments` | one row per journey and pair of consecutive stations | 3,420 | `exports/segments.csv` |
| `mart.network` | one row per station or section | 14 (6 stations, 8 sections) | `exports/network.csv` |

### 8.1 mart.stations

| Column | Type | Meaning | Example |
|---|---|---|---|
| `station_name` | Text | full name as in `core.stops` | `Nürnberg Hbf` |
| `station_short` | Text | short name for charts | `Nürnberg` |
| `latitude` | Numeric | approximate latitude, only for the map | `49.4460` |
| `longitude` | Numeric | approximate longitude, only for the map | `11.0825` |

### 8.2 mart.stops

All service types except bus (only 8 stops), without suspect delays: 25,106 - 10 - 8 = 25,088 rows.

| Column | Type | Meaning | Example |
|---|---|---|---|
| `station` | Text | short station name (full name if missing in the lookup) | `Regensburg` |
| `latitude`, `longitude` | Numeric | coordinates from `mart.stations` | `49.0118` |
| `line` | Text | line, for long distance category + number | `RE2` |
| `origin_station` | Text | first station of the journey | `München Hbf Gl.27-36` |
| `destination_station` | Text | last station of the journey | `Hof Hbf` |
| `service_type` | Text | long distance / regional / S-Bahn | `regional` |
| `scope` | Text | `BEG scope` (regional, S-Bahn) or `benchmark` (long distance) | `BEG scope` |
| `operator_brand` | Text | readable operator brand, derived from the category (approximation) | `agilis` |
| `train_category` | Text | category as delivered by the API | `RE` |
| `service_date` | Date | day of the planned stop | `2026-10-21` |
| `weekday_no` | Integer | 1 = Monday ... 7 = Sunday, for sorting | `3` |
| `weekday` | Text | short weekday name | `Wed` |
| `hour_of_day` | Integer | hour of the planned stop, 0-23 | `19` |
| `planned_event_at` | TIMESTAMP | planned departure, or planned arrival at the final stop | `2026-10-21 19:20:00` |
| `delay_min` | Integer | delay in minutes (negative = early), NULL if cancelled | `4` |
| `delay_category` | Text | early / on time / delayed 6-15 / delayed 16-60 / delayed > 60 / cancelled | `on time` |
| `on_time` | Integer | 1 = less than 6 min late, 0 = later, NULL if cancelled | `1` |
| `cancelled` | Integer | 1 = cancelled, 0 = ran | `0` |
| `is_platform_changed` | Integer | 1 = actual platform differs from planned platform | `0` |

Use in Tableau: on-time share = AVG(`on_time`), cancellation rate = AVG(`cancelled`), number of cancelled stops = SUM(`cancelled`), number of stops = COUNT.

### 8.3 mart.segments

BEG scope only (regional and S-Bahn), cancelled stops left out. "Consecutive" means the previous observed stop of the same journey among the six stations. Stops in between are not part of the data.

| Column | Type | Meaning | Example |
|---|---|---|---|
| `segment` | Text | direction of travel | `Hof → Nürnberg` |
| `from_station` | Text | previous station of the journey | `Hof` |
| `to_station` | Text | current station | `Nürnberg` |
| `line` | Text | line of the journey | `RE31` |
| `service_type` | Text | regional / S-Bahn | `regional` |
| `service_date` | Date | day of the stop at `to_station` | `2026-10-22` |
| `delay_before_min` | Integer | delay at `from_station` | `2` |
| `delay_after_min` | Integer | delay at `to_station` | `12` |
| `delay_change_min` | Integer | `delay_after_min - delay_before_min`; positive = the delay grew | `10` |

### 8.4 mart.network

One table with two kinds of rows: stations (points on the map) and sections (lines between two stations). Both directions of a section are combined. A section is only included if it has at least 20 journeys in each direction. `station_a` is always the alphabetically first station.

| Column | Type | Stations | Sections | Example |
|---|---|---|---|---|
| `element_type` | Text | `station` | `section` | `section` |
| `element_name` | Text | station name | `station_a - station_b` | `Hof - Nürnberg` |
| `station_a` | Text | station name | first station (alphabetical) | `Hof` |
| `station_b` | Text | NULL | second station | `Nürnberg` |
| `latitude`, `longitude` | Numeric | position of the station | start of the line (`station_a`) | `50.3082` |
| `to_latitude`, `to_longitude` | Numeric | NULL | end of the line (`station_b`) | `49.4460` |
| `stops` | Integer | stops in BEG scope | NULL | `2497` |
| `on_time_share` | Numeric | on-time share as a fraction | NULL | `0.829` |
| `cancellation_rate` | Numeric | cancellation rate as a fraction | NULL | `0.097` |
| `journeys` | Integer | NULL | journeys in both directions | `157` |
| `minutes_lost` | Numeric | NULL | average delay change, both directions | `8.7` |
| `minutes_lost_a_to_b` | Numeric | NULL | average delay change from `station_a` to `station_b` | `7.7` |
| `minutes_lost_b_to_a` | Numeric | NULL | average delay change from `station_b` to `station_a` | `10.1` |


---

## 9. Fields not stored as columns (available in raw_xml)

| XML | Where | Meaning | Status |
|---|---|---|---|
| `ar@fb` / `dp@fb` | `/plan` | display label of the line, e.g. `Bus RE50` | not needed |
| `ar@cpth` / `dp@cpth` | `/fchg` | changed route (e.g. skipped stations) | candidate for extension |
| `m@t`, `m@c` | `/fchg` | message type and code, e.g. delay reason | candidate for extension (see case study, section 6) |
| `m@ts` | `/fchg` | message timestamp | |

---

## 10. Relationships

```
staging.stg_plan                 staging.stg_changes
┌────────────────────┐           ┌────────────────────┐
│ PK eva             │◄─────────►│ PK eva             │
│ PK stop_id         │  1 : 0..1 │ PK stop_id         │
│    planned values  │           │    changed values  │
└─────────┬──────────┘           └─────────┬──────────┘
          └──────── LEFT JOIN ─────────────┘
                        ▼
                   core.stops
```






