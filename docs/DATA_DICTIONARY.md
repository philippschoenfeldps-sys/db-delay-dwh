# Data Dictionary - bahn-delay-dwh

> Reference for the used data in this project.

---

## 1. Overview

#
#
#

### Layer naming convention

| Layer | Column names | Data types | Purpose |
|---|---|---|---|
| staging | close to the source (`arr_pt`) | raw (mostly TEXT) | 1:1 copy of the API |
| core | readable (`planned_arrival_at`) | proper types (`TIMESTAMP`, `BOOLEAN`) | cleaned, joined, one truth |
| mart | business terms (`delay_minutes`) | aggregated / modeled | analysis & dashboards |

Why staging keeps the cryptic names: 
when a value looks wrong, you can compare the column directly with the API docs (arr_pt = <ar pt="...">). Readable names are introduced in the core layer, where the "suggested name" column is used.

---

## 2. Data source

| Item | Value |
| Provider| Deutsche Bahn, DB API Marketplace |
| API | Timetables 1.0.274 |
| Base URL | `https://apis.deutschebahn.com/db-api-marketplace/apis/timetables/v1` |
| Auth headers| `DB-Client-ID`, `DB-Api-Key` |
| Format | XML |
| Rate limit| free plan: 60 requests/minute |
| Full field reference | OpenAPI spec `Timetables-*.json` |

For futher information: `https://developers.deutschebahn.com/db-api-marketplace/apis/product/timetables`

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
| 8000261 | München Hbf | verify with `collector.py --check` |
| 8000284 | Nürnberg Hbf | verify with `collector.py --check` |
| 8000183 | Hof Hbf | verify with `collector.py --check` |
| 8000217 | Landshut(Bay)Hbf | verify with `collector.py --check` |
| 8089430 | Regensburg Hauptbahnhof (bus stop) | rail replacement buses (RE50), not collected yet |

## 3. XML structure

One response = one `<timetable>`, containing many `<s>`(stop) elements.

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

All times are text in the format yyMMddHHmm, in German local time.

```
2610191512
-> year: 2026
-> month: 10
-> day: 19
-> hour: 15
-> minutes: 12
```

SQL conversion: to_timestamp('2610191512', 'YYMMDDHH24MI')

### The stop ID

```
-3396501293033557189 - 2610191340 - 8
└──────── trip id ───┘ └ origin ─┘  └ stop index
                        departure     (position of this station on the route,
                        at first      1 = train starts here)
                        station
```

The trip id can start with a minus, so splitting the id on `-` needs care. Safer: take the last two parts and treat the rest as the trip id.

---

## 4. staging.stg_plan






