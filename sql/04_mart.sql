-- Mart Layer - Data prepared for the Tableau dashboard

-- Builds on: sql/02_core.sql (view core.stops)

-- Four views, the last three are exported as CSV files for Tableau Public:
--      mart.stations   one row per station             → short name and map coordinates
--      mart.stops      one row per stop                → KPIs, stations, lines, time, cancellations
--      mart.segments   one row per segment             → where delays build up (Q4)
--      mart.network    one row per station or section  → network map (points and lines)

-- Rules: same as in the analysis (sql/03_analysis.sql)

-- Run (cmd, from the repo root):
--  docker exec -i bahn-postgres psql -U bahn -d bahn_dwh < sql\04_mart.sql

CREATE SCHEMA IF NOT EXISTS mart;

DROP VIEW IF EXISTS mart.network;
DROP VIEW IF EXISTS mart.segments;
DROP VIEW IF EXISTS mart.stops;
DROP VIEW IF EXISTS mart.stations;


-- VIEW: mart.stations --

-- Short names for readable charts (e.g., "München" instead of "München Hbf").
-- Coordinates are approximate and only used to place the stations on a map.
CREATE VIEW mart.stations (station_name, station_short, latitude, longitude) AS 
VALUES
    ('München Hbf',      'München',    48.1403, 11.5600),
    ('Nürnberg Hbf',     'Nürnberg',   49.4460, 11.0825),
    ('Regensburg Hbf',   'Regensburg', 49.0118, 12.0998),
    ('Ingolstadt Hbf',   'Ingolstadt', 48.7442, 11.4373),
    ('Landshut(Bay)Hbf', 'Landshut',   48.5475, 12.1375),
    ('Hof Hbf',          'Hof',        50.3082, 11.9228);


-- VIEW: mart.stops --

-- One row per stop (with short names and numeric 0/1 flags for Tableau).
CREATE VIEW mart.stops AS
SELECT
    -- WHERE --
    COALESCE(st.station_short, c.station_name)      AS station,           -- a station missing in the lookup keeps its full name instead of silently disappearing
    st.latitude,
    st.longitude,
    c.line,
    c.origin_station,
    c.destination_station,

    -- WHO --
    c.service_type,

    -- BEG contracts regional trains and S-Bahn (long distance is only a benchmark)
    CASE WHEN c.service_type IN ('regional', 'S-Bahn') THEN 'BEG scope' 
        ELSE 'benchmark'
    END                                             AS scope,

    -- readable operator brand, derived from the train category
    -- (an approximation: one category can include several operators)
    CASE c.train_category
        WHEN 'ag'  THEN 'agilis'
        WHEN 'ARV' THEN 'Arverio'
        WHEN 'ALX' THEN 'alex'
        WHEN 'OPB' THEN 'oberpfalzbahn'
        WHEN 'BRB' THEN 'Bayerische Regiobahn'
        WHEN 'MRB' THEN 'Mitteldeutsche Regiobahn'
        WHEN 'EB'  THEN 'Erfurter Bahn'
        WHEN 'VBG' THEN 'Vogtlandbahn'
        WHEN 'S'   THEN 'S-Bahn'
        WHEN 'RE'  THEN 'RE/RB (mostly DB Regio)'
        WHEN 'RB'  THEN 'RE/RB (mostly DB Regio)'
        ELSE c.train_category                                                   -- long distance: ICE, IC ...
    END                                             AS operator_brand,
    c.train_category,                            

    -- WHEN --
    c.service_date,
    extract(isodow FROM c.service_date)::int        AS weekday_no,              -- 1 = Monday (for sorting)     
    to_char(c.service_date, 'Dy')                   AS weekday,                 -- Mon, Tue ...
    extract(hour FROM c.planned_event_at)::int      AS hour_of_day,
    c.planned_event_at,

    -- HOW PUNCTUAL --
    c.delay_min,
    c.delay_category,
    c.is_on_time::int                               AS on_time,                 -- 1 / 0, NULL if cancelled
    c.is_cancelled::int                             AS cancelled,               -- 1 / 0
    c.is_platform_changed::int                      AS is_platform_changed      -- 1 / 0 

FROM
    core.stops c
LEFT JOIN
    mart.stations st ON st.station_name = c.station_name
WHERE NOT 
    c.is_suspect_delay
    AND c.service_type <> 'bus';                    -- only 8 bus stops (too few to show)


-- VIEW: mart.segments --

CREATE VIEW mart.segments AS
WITH stops_in_order AS (
    SELECT
        c.trip_id,
        c.line,
        c.service_type,
        c.service_date,
        c.delay_min,
        COALESCE(st.station_short, c.station_name)                              AS station,     -- station and delay of the previous observed stop of the same journey
        LAG(COALESCE(st.station_short, c.station_name))
            OVER (PARTITION BY c.trip_id ORDER BY c.planned_event_at)           AS prev_station,
        LAG(c.delay_min)
            OVER (PARTITION BY c.trip_id ORDER BY c.planned_event_at)           AS prev_delay_min
    FROM 
        core.stops c
    LEFT JOIN
        mart.stations st ON st.station_name = c.station_name
    WHERE NOT 
        c.is_suspect_delay
        AND NOT c.is_cancelled
        AND c.service_type IN ('regional', 'S-Bahn')                            -- BEG scope
)
SELECT
    prev_station || ' → ' || station                                            AS segment,
    prev_station                                                                AS from_station,
    station                                                                     AS to_station,
    line,
    service_type,
    service_date,
    prev_delay_min                                                              AS delay_before_min,
    delay_min                                                                   AS delay_after_min,
    delay_min - prev_delay_min                                                  AS delay_change_min     -- > 0: delay grew on this segment
FROM 
    stops_in_order
WHERE 
    prev_station IS NOT NULL;


-- VIEW: mart.network --

-- One row per station (point) and one row per section (line between two neighbouring stations) for the network map.
-- Both directions of a section are combined. The minutes per direction are kept for the tooltip.
CREATE VIEW mart.network AS
WITH station_stats AS (

    -- punctuality per station, BEG scope, same rules as the analysis
    SELECT
        st.station_short                                                        AS station,
        st.latitude,
        st.longitude,
        count(*)                                                                AS stops,
        round(avg(c.is_on_time::int), 3)                                        AS on_time_share,   -- 0.856 = 85.6 %
        round(avg(c.is_cancelled::int), 3)                                      AS cancellation_rate
    FROM 
        core.stops c
    JOIN 
        mart.stations st ON st.station_name = c.station_name
    WHERE 
        c.service_type IN ('regional', 'S-Bahn')
        AND NOT c.is_suspect_delay
    GROUP BY 
        st.station_short, 
        st.latitude, 
        st.longitude
),
section_stats AS (

    -- both directions of a section are put in one group: "Nürnberg -> Hof" and "Hof -> Nürnberg" both become (Hof, Nürnberg)
    SELECT
        LEAST(from_station, to_station)                                          AS station_a,
        GREATEST(from_station, to_station)                                       AS station_b,
        count(*)                                                                 AS journeys,
        round(avg(delay_change_min), 1)                                          AS minutes_lost,       -- both directions
        round(avg(delay_change_min) FILTER (WHERE from_station < to_station), 1) AS minutes_lost_a_to_b,
        round(avg(delay_change_min) FILTER (WHERE from_station > to_station), 1) AS minutes_lost_b_to_a
    FROM 
        mart.segments
    GROUP BY 
        station_a, 
        station_b
    HAVING 
        count(*) FILTER (WHERE from_station < to_station) >= 20
        AND count(*) FILTER (WHERE from_station > to_station) >= 20              -- only sections with enough journeys (in both directions)
)
-- stations: one point each
SELECT
    'station'                   AS element_type,
    station                     AS element_name,
    station                     AS station_a,
    NULL::text                  AS station_b,
    latitude,
    longitude,
    NULL::numeric               AS to_latitude,
    NULL::numeric               AS to_longitude,
    stops,
    on_time_share,
    cancellation_rate,
    NULL::bigint                AS journeys,
    NULL::numeric               AS minutes_lost,
    NULL::numeric               AS minutes_lost_a_to_b,
    NULL::numeric               AS minutes_lost_b_to_a
FROM station_stats

UNION ALL

-- sections: a line from station a to station b
SELECT
    'section',
    s.station_a || ' - ' || s.station_b,
    s.station_a,
    s.station_b,
    a.latitude,
    a.longitude,
    b.latitude,
    b.longitude,
    NULL, NULL, NULL,
    s.journeys,
    s.minutes_lost,
    s.minutes_lost_a_to_b,
    s.minutes_lost_b_to_a
FROM 
    section_stats s
JOIN 
    mart.stations a ON a.station_short = s.station_a                                -- start point
JOIN 
    mart.stations b ON b.station_short = s.station_b;                               -- end point


COMMENT ON VIEW mart.stations IS 'Lookup of the six stations: short name and approximate coordinates';
COMMENT ON VIEW mart.stops    IS 'Dashboard data: one row per stop, flags as 0/1. Export: exports/stops.csv';
COMMENT ON VIEW mart.segments IS 'Dashboard data: delay change between consecutive stations of a journey. Export: exports/segments.csv';
COMMENT ON VIEW mart.network  IS 'Network map: stations as points, sections as lines with minutes lost. Export: exports/network.csv';



