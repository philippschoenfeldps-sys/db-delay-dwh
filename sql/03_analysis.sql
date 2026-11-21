-- Analysis Layer - One Query per Guiding Question (Q1 - Q6)

-- Builds on: sql/02_core.sql (view core stops)

-- Questions: docs/CASE_STUDY.md, section 1.6

-- Scope: regional trains and S-Bahn (contracted by BEG).
--        Long-distance trains only appear as a benchmark in Q6.

-- Rules:   - stops flagged as is_suspect_delay are left out (see CHANGELOG v1.1)
--          - on-time share and delays only count stops that were not cancelled
--          - every result shows its number of stops (n), because coverage differs by day and hour (see CASE_STUDY section 2.5)

-- Run (cmd, from the repo root):
--  docker exec -i bahn-postgres psql -U bahn -d bahn_dwh < sql\03_analysis.sql


-- Analysis base: a temporary table with all stops in scope.
-- A temporary table exists only for this session (this one run of the file) and is so deleted automatically afterwards.
-- All queries below read from it, so the scope is defined in one place only.
DROP TABLE IF EXISTS regional_stops;

CREATE TEMP TABLE regional_stops AS
SELECT
    *
FROM
    core.stops
WHERE 
    service_type IN ('regional', 'S-Bahn')        -- BEG scope
    AND NOT is_suspect_delay;

-- size of the analysis base --
SELECT 
    count (*)                   AS stops_in_scope
FROM    
    regional_stops;


-- Q1: How punctual is regional rail at each of the six stations? -- 

SELECT
    station_name,
    count(*)                                                                        AS n,
    round(100 * avg(is_on_time::int), 1)                                            AS on_time_pct,
    round(100.0 * count(*) FILTER (WHERE is_cancelled) / count(*), 1)               AS cancelled_pct,
    round(avg(delay_min), 1)                                                        AS avg_delay_min,
    round((percentile_cont(0.5) WITHIN GROUP (ORDER BY delay_min))::numeric, 1)     AS median_delay_min     -- median
FROM
    regional_stops
GROUP BY 
    station_name
ORDER BY
    on_time_pct;            -- worst station first


-- Q2a: Which lines perform worst at each station? --

WITH line_stats AS (
    SELECT
        station_name,
        line,
        count(*)                                AS n,
        round(100 * avg(is_on_time::int), 1)    AS on_time_pct,
        round(avg(delay_min), 1)                AS avg_delay_min
    FROM 
        regional_stops
    GROUP BY 
        station_name,
        line
    HAVING
        count(*) >= 20                           -- ignore lines with very few stops
),
ranked AS (
    SELECT
        *,

        -- number the rows inside each & PARTITION (each station) by the ORDER BY, without merging them
        RANK() OVER (PARTITION BY station_name ORDER BY on_time_pct)    AS rank_at_station
    FROM
        line_stats
)
SELECT
    station_name,
    rank_at_station,
    line,
    n,
    on_time_pct,
    avg_delay_min
FROM
    ranked
WHERE
    rank_at_station <= 3                        -- the three worst lines per station
ORDER BY
    station_name,
    rank_at_station;


-- Q2b: Which operators (train categories) perform worst? --

--      The category is used as an approcimation of the operator brand:
--      ag = agilis, ARV = Arverio, ALX = alex, OPB = oberpfalzbahn, BRB = Bayrische Regiobahn, 
--      MRB = Mitteldeutsche Regiobahn, EB = Erfurter Bahn, RE/RB = mostly DB Regio, S = S-Bahn.
--      → One category can include several operators.

SELECT
    RANK() OVER (ORDER BY avg(is_on_time::int))     AS rank,        -- 1 = least punctual
    train_category,
    count(*)                                        AS n,
    count(DISTINCT line)                            AS lines,
    round(100 * avg(is_on_time::int), 1)            AS on_time_pct,
    round(avg(delay_min), 1)                        AS avg_delay_min
FROM 
    regional_stops
GROUP BY
    train_category
HAVING
    count(*) >= 100
ORDER BY
    rank;

--      Least punctual lines across all six stations (lines with less than 20 stops are left out)

SELECT
    line,
    count(*)                                                    AS n,              -- all planned stops of the line
    round(100.0 * avg(is_on_time::int), 1)                      AS on_time_pct,    -- NULL (cancelled) is ignored by avg
    round(100.0 * avg(is_cancelled::int), 1)                    AS cancelled_pct,  -- share of all planned stops
    round(avg(delay_min) FILTER (WHERE NOT is_cancelled), 1)    AS avg_delay_min
FROM 
    regional_stops
GROUP BY 
    line
HAVING 
    count(*) >= 20                                              -- minimum sample size
ORDER BY 
    on_time_pct                                                 -- worst first
LIMIT 
    10;
    

-- Q3a: When do delays occur (by hour of day)? --

--      days_with_data shows how reliable each hour is (sampling bias, see 2.5)

SELECT
    extract(hour FROM planned_event_at)::int        AS hour_of_day,
    count(*)                                        AS n,
    count(DISTINCT service_date)                    AS days_with_data,
    round(100 * avg(is_on_time::int), 1)            AS on_time_pct,
    round(avg(delay_min), 1)                        AS avg_delay_min
FROM
    regional_stops
GROUP BY
    hour_of_day
ORDER BY
    hour_of_day;


-- Q3b: When do delays occur (by weekday)? --

SELECT
    extract(isodow FROM service_date)::int          AS weekday_no,      -- 1 = Monday, ..., 7 = Sunday (for correct sort order)
    to_char(service_date, 'Dy')                     AS weekday,
    count(*)                                        AS n,
    count(DISTINCT service_date)                    AS days_with_data,
    round(100 * avg(is_on_time::int), 1)            AS on_time_pct,
    round(avg(delay_min), 1)                        AS avg_delay_min
FROM
    regional_stops
GROUP BY
    weekday_no,
    weekday
ORDER BY
    weekday_no;


-- Q4: Do delays build up along a route? --

--     Some trips pass several of the six stations (e.g. RE2 München → Landshut → Regensburg → Hof).
--     LAG () looks at the previous row of the same trip, in order to compare the delay at one station with the delay at the station before.

WITH stops_in_order AS (
    SELECT
        trip_id,
        line,
        station_name,
        planned_event_at,
        delay_min,
        
        -- station and delay of the previous observed stop of the same trip
        LAG(station_name) OVER (PARTITION BY trip_id ORDER BY planned_event_at)     AS prev_station,
        LAG(delay_min)    OVER (PARTITION BY trip_id ORDER BY planned_event_at)     AS prev_delay_min
    FROM
        regional_stops
    WHERE NOT
        is_cancelled
)
SELECT
    prev_station || ' → ' || station_name           AS segment,
    count(*)                                        AS n_trips,
    round(avg(prev_delay_min), 1)                   AS avg_delay_before,
    round(avg(delay_min), 1)                        AS avg_delay_after,
    round(avg(delay_min - prev_delay_min), 1)       AS avg_change_min       -- > 0: delay grows on this segment
FROM
    stops_in_order
WHERE
    prev_station IS NOT NULL                        -- only stops with a previous station
GROUP BY
    segment
HAVING
    count(*) >= 20
ORDER BY
    avg_change_min DESC;


-- Q5a: How large is the impact of cancellations, and are they systematic? --

--     A line that is (almost) always cancelled at a station points to a planned closure (e.g. construction), 
--     not to random disruptions.

SELECT
    station_name,
    line,
    count(*)                                                            AS n,
    count(*) FILTER (WHERE is_cancelled)                                AS cancelled,
    round(100.0 * count(*) FILTER (WHERE is_cancelled) / count(*), 1)   AS cancelled_pct,
    CASE
        WHEN 100.0 * count(*) FILTER (WHERE is_cancelled) / count(*) >= 90 THEN 'systematic'
        ELSE 'occasional'
    END                                                                 AS pattern
FROM 
    regional_stops
GROUP BY 
    station_name, 
    line
HAVING 
    count(*) FILTER (WHERE is_cancelled) >= 5                            -- at least 5 cancellations
ORDER BY 
    cancelled_pct DESC;


-- Q5b: Hof - are the cancellations limited to a certain period? --

--      One row per day, one column pair per line: a pivot table in SQL.

SELECT
    service_date,
    count(*) FILTER (WHERE line = 'RB97')                       AS rb97_n,
    count(*) FILTER (WHERE line = 'RB97' AND is_cancelled)      AS rb97_cancelled,
    count(*) FILTER (WHERE line = 'RE31')                       AS re31_n,
    count(*) FILTER (WHERE line = 'RE31' AND is_cancelled)      AS re31_cancelled,
    count(*) FILTER (WHERE line = 'RE2')                        AS re2_n,
    count(*) FILTER (WHERE line = 'RE2'  AND is_cancelled)      AS re2_cancelled
FROM 
    regional_stops
WHERE 
    station_name = 'Hof Hbf'
GROUP BY 
    service_date
ORDER BY 
    service_date;


-- Q6: How does regional rail compare to long-distance and S-Bahn? --

--     Reads core.stops directly, because long-distance is outside the analysis base. 
--     Suspect delays are left out here as well.

SELECT
    service_type,
    count(*)                                                                        AS n,
    round(100 * avg(is_on_time::int), 1)                                            AS on_time_pct,
    round(100.0 * count(*) FILTER (WHERE is_cancelled) / count(*), 1)               AS cancelled_pct,
    round(avg(delay_min), 1)                                                        AS avg_delay_min,
    round((percentile_cont(0.5) WITHIN GROUP (ORDER BY delay_min))::numeric, 1)     AS median_delay_min,
    round((percentile_cont(0.9) WITHIN GROUP (ORDER BY delay_min))::numeric, 1)     AS p90_delay_min
FROM 
    core.stops
WHERE NOT 
    is_suspect_delay
  AND 
    service_type <> 'bus'
GROUP BY 
    service_type
ORDER BY 
    on_time_pct;

