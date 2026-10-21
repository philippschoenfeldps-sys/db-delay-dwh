-- Core Layer - One Clean Row per Stop

-- Builds on: sql/01_staging.sql (staging.stg_plan, staging.stg_changes)

-- core.stops is a VIEW: a stored query, no data of its own.
-- Every query on core.stops reads the current staging data, so the view is always up to date without reloading anything.

-- Grain        one row = one stop of one train at one station
-- Key          (station_eva, stop_id)

-- Assumptions
--  1. Times are German local time without time zone (as delivered by the API).
--  2. No known changes for a stop -> the train is assumed to run as planned.
--     has_change_record shows where this assumption was needed.
--  3. One time = less than 6 minutes late (definition used by Deutsche Bahn).
--     Cancelled stops have no delay and are not counted as on time or late.
--  4. Long-distance trains have no line in the API. Line falls back to category + number (e.g., 'ICE 1000').

-- Run (cmd, from the repo root):
--  docker exec -i bahn-postgres psql -U bahn -d bahn_dwh < sql\02_core.sql
-- (the script can be run again at any time, it rebuilds the view)

CREATE SCHEMA IF NOT EXISTS core;

-- CREATE OR REPLACE VIEW cannot remove or reorder columns, so during development the view is dropped and created again.
DROP VIEW IF EXISTS core.stops;

CREATE VIEW core.stops AS

WITH plan AS (
    -- planned stops: readable names, real timestamps (STAGE 1)
    SELECT
        eva                                                             AS station_eva,
        station_name,                                                                               -- already readable
        stop_id,
        category                                                        AS train_category,
        trip_number                                                     AS train_number,            -- stays text
        COALESCE(arr_line, dep_line, category || ' ' || trip_number)    AS line,                    -- line is stored twice (arrival + departure) & long-distance trains have no line attribute in the API (category + number)
        to_timestamp(arr_pt, 'YYMMDDHH24MI')::timestamp                 AS planned_arrival_at,      -- text ('2610191512') -> timestamp (2026-10-19 15:12:00)
        to_timestamp(dep_pt, 'YYMMDDHH24MI')::timestamp                 AS planned_departure_at,
        COALESCE(dep_pp, arr_pp)                                        AS planned_platform,
        arr_ppth,                                                                                   -- route before this station
        dep_ppth                                                                                    -- route after this station
    
    FROM staging.stg_plan
),

changes AS (
    -- real-time changes: same cleaning (stage 3)
    SELECT
        eva                                                 AS station_eva,
        stop_id,
        to_timestamp(arr_ct, 'YYMMDDHH24MI')::timestamp     AS changed_arrival_at,
        to_timestamp(dep_ct, 'YYMMDDHH24MI')::timestamp     AS changed_departure_at,
        COALESCE(dep_cp, arr_cp)                            AS changed_platform,
        arr_cs                                              AS arrival_status,          -- p = planned, a = added, c = cancelled
        dep_cs                                              AS departure_status,
        last_seen_at                                        AS change_last_seen_at      -- how fresh is the real-time info?
    
    FROM staging.stg_changes
),

joined AS (
    -- plan + changes (LEFT JOIN keeps stops without changes), actual values, derived plan fields (STAGE 2 & 3)
    SELECT
        p.station_eva,
        p.station_name,
        p.stop_id,

        -- TRIP --

        -- split the stop id: <trip id>-<origin departure>-<stop index>
        regexp_replace(p.stop_id, '-\d+-\d+$', '')                                          AS trip_id,
        to_timestamp(substring(p.stop_id FROM '-(\d{10})-\d+$'), 'YYMMDDHH24MI')::timestamp AS trip_started_at,
        substring(p.stop_id FROM '-(\d+)$')::int                                            AS stop_index,
        
        p.train_category,
        p.train_number,
        p.line,
        COALESCE((string_to_array(p.arr_ppth, '|'))[1], p.station_name)                     AS origin_station,
        COALESCE((string_to_array(p.dep_ppth, '|'))[cardinality(string_to_array(p.dep_ppth, '|'))], p.station_name)                                          AS destination_station,

        -- TIME --

        -- operating day of this stop (timestamp -> date)
        COALESCE(p.planned_departure_at, p.planned_arrival_at)::date    AS service_date,

        -- the moment the train is at the station: departure, or arrival if it ends here
        COALESCE(p.planned_departure_at, p.planned_arrival_at)          AS planned_event_at,

        -- arrival & departure: planned vs. changed vs. actual
        p.planned_arrival_at,
        p.planned_departure_at,
        COALESCE(c.changed_arrival_at,   p.planned_arrival_at)          AS actual_arrival_at,
        COALESCE(c.changed_departure_at, p.planned_departure_at)        AS actual_departure_at,

        -- PLATFORM --

        -- changed platform if there is one, otherwise the planned one
        p.planned_platform,
        COALESCE(c.changed_platform, p.planned_platform)                AS actual_platform,

        -- STATUS & FLAGS --

        c.arrival_status,
        c.departure_status,

        -- no arrival -> train starts
        p.planned_arrival_at    IS NULL                                         AS is_origin,

        -- no departure -> train ends
        p.planned_departure_at  IS NULL                                         AS is_terminus,

        -- bus instead of train
        p.train_category = 'Bus'                                                AS is_rail_replacement,

        COALESCE(c.arrival_status = 'c' OR c.departure_status = 'c', false)     AS is_cancelled,

        -- did the API report anything at all for this stop?
        c.stop_id               IS NOT NULL                                     AS has_change_record,

        c.change_last_seen_at

    FROM plan p                                                                 -- p = short alias for plan
    LEFT JOIN changes c                                                         -- keep all planned stops, even without changes
           ON  c.station_eva = p.station_eva                                    -- same station AND
           AND c.stop_id     = p.stop_id                                        -- same stop    -> same row
),

delays AS (
    -- delays in minutes, calculated once so later steps can reuse them (STAGE 4)
    SELECT
        j.*,                                                                    -- all columns of joined
        CASE WHEN j.is_cancelled THEN NULL
             ELSE (EXTRACT(EPOCH FROM j.actual_arrival_at - j.planned_arrival_at) / 60)::int
        END AS arrival_delay_min,
        CASE WHEN j.is_cancelled THEN NULL
             ELSE (EXTRACT(EPOCH FROM j.actual_departure_at - j.planned_departure_at) / 60)::int
        END AS departure_delay_min
    FROM joined j
)

SELECT
    -- IDENTIFICATION --
    station_eva,
    station_name,
    stop_id,
    trip_id,
    trip_started_at,
    stop_index,

    -- TRAIN --

    -- type of service, derived from the category.
    -- the list of long-distance categories comes from the data (STAGE 6).
    --  SELECT train_category, count(*) FROM core.stops GROUP BY 1;
    CASE
        WHEN train_category = 'Bus'                         THEN 'bus'
        WHEN train_category IN ('ICE', 'IC', 'EC', 'ECE',
                                'RJ', 'RJX', 'EN', 'NJ',
                                'WB', 'FLX', 'TGV')         THEN 'long distance'
        WHEN train_category = 'S'                           THEN 'S-Bahn'
        ELSE                                                     'regional'
    END AS service_type,

    train_category,
    train_number,
    line,
    origin_station,
    destination_station,

    -- TIME --
    service_date,
    planned_event_at,
    planned_arrival_at,
    actual_arrival_at,
    planned_departure_at,
    actual_departure_at,

    -- PLATFORM --
    planned_platform,
    actual_platform,
    actual_platform IS DISTINCT FROM planned_platform AS is_platform_changed,

    -- DELAY --

    -- reference is the arrival, or the departure if the train starts here
    arrival_delay_min,
    departure_delay_min,
    COALESCE(arrival_delay_min, departure_delay_min) AS delay_min,

    -- on time = less than 6 minutes late
    -- NULL for cancelled stops, so they are left out of averages automatically
    CASE WHEN is_cancelled THEN NULL
         ELSE COALESCE(arrival_delay_min, departure_delay_min) < 6
    END AS is_on_time,

    -- CATEGORY --

    -- the first matching WHEN wins
    CASE
        WHEN is_cancelled                                          THEN 'cancelled'
        WHEN COALESCE(arrival_delay_min, departure_delay_min) < 0  THEN 'early'
        WHEN COALESCE(arrival_delay_min, departure_delay_min) < 6  THEN 'on time'
        WHEN COALESCE(arrival_delay_min, departure_delay_min) < 16 THEN 'delayed 6-15'
        WHEN COALESCE(arrival_delay_min, departure_delay_min) < 61 THEN 'delayed 16-60'
        ELSE                                                            'delayed > 60'
    END AS delay_category,

    -- STATUS & FLAGS
    arrival_status,
    departure_status,
    is_origin,
    is_terminus,
    is_rail_replacement,
    is_cancelled,
    has_change_record,
    change_last_seen_at
 
FROM delays;

-- Short description, visible in psql with \d+ core.stops
COMMENT ON VIEW core.stops IS
    'One row per stop of one train at one station: planned vs. actual times, delays, cancellations. Built from staging.stg_plan + staging.stg_changes.';