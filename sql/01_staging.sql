-- Staging Layer - Staging Tables for the Raw API Data 

-- Designed from the inventory of the raw samples:
--  samples/*.xml   -> ingestion/inspect_xml.py -> docs/DATA_DICTIONARY.md

-- Design decisions
--  Grain           one row = one stop of one train at one station
--  Primary key     (eva, stop_id)
--  Columns         one column per XML attribute; 
--                  prefixes arr_/dep_because <ar> and <dp> use the same attribute names (pt, pp, l ...)
--  NULL            allowed wherever the inventory shows < 100% (e.g., no arrival when a train starts at this station)
--  Types           raw values stay TEXT: times like '2610191535' (yyMMddHHmm),
--                  platforms like '8 D-F'. 
--                  Converting and cleaning happens in a later layer, so the raw data can always be reprocessed.
--  Repeats         the same stop arrives in several requests -> it is updated, not duplicated (first_seen_at / last_seen_at track this)

-- Run it in the database bahn_dwh, e.g.: psql -d bahn_dwh -f sql/01_staging.sql
-- (the script is idempotent: running it again changes nothing)

-- Separate schema = separate "namespace" for raw data.
-- Later layers (core, mart) get their own schemas.
CREATE SCHEMA IF NOT EXISTS staging;


-- Planned stops from /plan{eval}/{yyMMdd}/{HH}

CREATE TABLE IF NOT EXISTS staging.stg_plan (
    -- identification
    eva            INTEGER     NOT NULL,   -- requested station (e.g. 8000309 = Regensburg Hbf)
    stop_id        TEXT        NOT NULL,   -- s@id: tripId-originDeparture-stopIndex
    station_name   TEXT,                   -- @station of <timetable>
 
    -- trip label: s/tl@...
    trip_type      TEXT,                   -- tl@t (p = planned)
    filter_flags   TEXT,                   -- tl@f (D, N, F, S ...)
    owner          TEXT,                   -- tl@o operator code
    category       TEXT,                   -- tl@c e.g. ICE, RE, ag, Bus
    trip_number    TEXT,                   -- tl@n (a number nobody calculates with -> TEXT)
 
    -- arrival: s/ar@...  (NULL if the train starts here)
    arr_pt         TEXT,                   -- planned time yyMMddHHmm
    arr_pp         TEXT,                   -- planned platform
    arr_line       TEXT,                   -- line, e.g. RE2
    arr_ppth       TEXT,                   -- planned path before this station, '|' separated
 
    -- departure: s/dp@...  (NULL if the train ends here)
    dep_pt         TEXT,
    dep_pp         TEXT,
    dep_line       TEXT,
    dep_ppth       TEXT,                   -- planned path after this station
 
    -- technical columns (not from the API)
    raw_xml        TEXT        NOT NULL,                -- full <s> element: nothing gets lost
    first_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),  -- first time this stop was fetched
    last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT now(),  -- updated on every re-fetch
 
    -- the same stop_id can appear at different stations, so the key needs both
    PRIMARY KEY (eva, stop_id)
);
 

-- Real-time changes from /fchg/{eva}

-- Only the latest known state per stop is kept.
-- Same key as stg_plan -> both tables join on (eva, stop_id).

CREATE TABLE IF NOT EXISTS staging.stg_changes (
    eva            INTEGER     NOT NULL,
    stop_id        TEXT        NOT NULL,   -- same id as stg_plan.stop_id
    station_name   TEXT,
 
    -- trip label: rarely present in changes (mostly for added trips)
    category       TEXT,
    trip_number    TEXT,
 
    -- arrival changes: s/ar@...
    arr_ct         TEXT,                   -- changed time yyMMddHHmm
    arr_cp         TEXT,                   -- changed platform
    arr_cs         TEXT,                   -- changed status: p = planned, a = added, c = cancelled
    arr_clt        TEXT,                   -- cancellation time
    arr_line       TEXT,
 
    -- departure changes: s/dp@...
    dep_ct         TEXT,
    dep_cp         TEXT,
    dep_cs         TEXT,
    dep_clt        TEXT,
    dep_line       TEXT,
 
    raw_xml        TEXT        NOT NULL,                -- includes <m> messages (delay reasons etc.)
    first_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
 
    PRIMARY KEY (eva, stop_id)
);
 
 
-- Ingestion log: one row per API request of the automated loader.

-- Answers "did last night's runs work?" without reading log files.

CREATE TABLE IF NOT EXISTS staging.ingestion_log (
    log_id         BIGSERIAL   PRIMARY KEY,   -- no natural key -> auto-increment number
    run_started_at TIMESTAMPTZ NOT NULL,      -- groups all requests of one run
    endpoint       TEXT        NOT NULL,      -- 'plan' or 'fchg'
    eva            INTEGER     NOT NULL,
    request_slot   TEXT,                      -- e.g. '261019/15' for plan, NULL for fchg
    http_status    INTEGER,                   -- NULL if no response arrived at all
    rows_received  INTEGER,
    error_message  TEXT,
    logged_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);