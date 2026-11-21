# Case Study: Punctuality of Regional Rail at Six Bavarian Hubs

Google Data Analytics Professional Certificate - Capstone Project (own case study)

Author: Philipp Schönfeld
Data period: 20 Oct - 6 Nov 2026
Tools: Python (data collection), PostgreSQL 17 in Docker (storage, cleaning, analysis), SQL, Tableau Public (visualisation), GitHub (version control, documentation)

The case study follows the Case Study Roadmap of the certificate. The six phases of the data analysis process:

Ask  →  Prepare  →  Process  →  Analyze  →  Share  →  Act

Each phase includes guiding questions, key tasks and a deliverable.


| Phase | Deliverable (from the roadmap) | Where in this repo |
|---|---|---|
| [1. Ask](#1-ask) | A clear statement of the business task | this document |
| [2. Prepare](#2-prepare) | A description of all data sources used | `ingestion/`, `docs/DATA_DICTIONARY.md` |
| [3. Process](#3-process) | Documentation of any cleaning or manipulation of data | `sql/01_staging.sql`, `sql/02_core.sql`, `docs/CHANGELOG.md` |
| [4. Analyze](#4-analyze) | A summary of the analysis | `sql/03_analysis.sql` |
| [5. Share](#5-share) | Supporting visualisations and key findings | Tableau Public dashboard, `sql/04_mart.sql` |
| [6. Act](#6-act) | Top high-level insights, recommendations and further deliverables | this document |

---

## 1. Ask

### 1.1 Scenario

I act as a junior data analyst at a business intelligence consultancy. The client is the **Bayerische Eisenbahngesellschaft (BEG)**, which plans, finances and monitors all regional rail passenger services in Bavaria on behalf of the Bavarian State Ministry. BEG contracts the train operators, evaluates their quality reports, checks its quality standards and uses financial incentives to motivate operators on service quality and punctuality ([StMB](https://stmb.bayern.de/vum/schiene/nahverkehr/index.php)).
 
**The real-world gap.** BEG rewards or penalises operators based on a published service quality ranking. This ranking rates only what operators control directly, such as cleanliness, passenger information, equipment and complaint handling. Punctuality and cancellations are deliberately left out and recorded in a separate system ([Railway PRO](https://railwaypro.com/wp/?p=123538)).

The reason is that a delay can be caused either by the operator (e.g. staff shortages, broken train) or by the infrastructue (e.g. signal failure, track works). A punctuality figure mixes both cases. Therefore, basing bonuses or penalties on it would also punish operators for problems they cannot control.

As a result, the quality aspect that matters most to passengers sits outside BEG's main steering instrument. This project uses open real-time data to show where and when punctuality falls short, and gives hints whether a problem lies with the operator or the infrastructure. It does not replace BEG's internal monitoring, but offers an independent, fine-grained view.
 
### 1.2 Five questions that frame the case study

|   | Roadmap question | Answer |
|---|---|---|
| 1 | What type of company is the client, and what are they asking for? | A public transport authority (BEG) that contracts regional rail. It wants to know where punctuality falls short, to prioritise talks with operators and infrastructure. |
| 2 | What are the key factors in the business task? | Station, line, operator, service type, time of day, weekday, delays along a route, cancellations |
| 3 | What type of data is appropriate? | Planned and actual arrival/departure times per stop, with cancellation status → quantitative, structured, time-based data |
| 4 | Where will the data come from? | DB Timetables API (DB API Marketplace), collected hourly with an own Python collector into PostgreSQL |
| 5 | Who is the audience, and which materials help? | BEG management and quality team → case study document, interactive Tableau dashboard, short presentation |

### 1.3 Problem types

Of the six common problem types from the certificate, this case study combines three:

| Problem type | Where it appears |
|---|---|
| Finding patterns | when and where delays occur (hour, weekday, station, line) |
| Spotting something unusual | lines with unusually high cancellation rates, outliers in delay |
| Categorizing things | grouping trains into service types and operators to compare them fairly |

### 1.4 Stakeholders

| Stakeholder | Stakeholder group | Interest in the results |
|---|---|---|
| BEG management (primary) | executive team | headline findings first: where is the biggest problem, what to do |
| BEG quality management | customer-facing team (works directly with the operators) | which lines and operators miss punctuality, evidence for talks |
| BEG network planning | data / planning team | when and where delays build up |
| Train operators (e.g. agilis, DB Regio, Die Länderbahn, BRB, Arverio) | external | how they compare to other operators |
| Infrastructure manager | external | whether problems are tied to stations or routes |
| Passengers / commuters | end users | how reliable their connection is |

### 1.5 Business task

Identify where, when and on which regional lines punctuality at six major Bavarian rail hubs falls short, so that BEG can prioritise quality talks with operators and flag infrastructure bottlenecks.

### 1.6 Guiding questions

The questions follow the **SMART** methodology: specific, measurable, action-oriented, relevant and time-bound (all refer to 20 Oct - 6 Nov 2026).

|   | Question | Metric | Planned SQL technique |
|---|---|---|---|
| Q1 | How punctual is regional rail at each of the six stations? | on-time share, cancellation rate | GROUP BY, aggregates |
| Q2 | Which lines and operators perform worst? | on-time share, average delay per line / operator, ranked | window function RANK() |
| Q3 | When do delays occur (by hour of day and weekday)? | on-time share per hour / weekday | EXTRACT |
| Q4 | Do delays build up along a route? | change of delay from stop to stop within one trip | window function LAG() over trip_id |
| Q5 | How large is the impact of cancellations, and are they systematic? | cancellation rate per line, lines with near-100 % cancellation | FILTER, HAVING |
| Q6 | How does regional rail compare to long-distance and S-Bahn? | on-time share per service type | GROUP BY service_type |

### 1.7 Metrics

| Metric | Definition |
|---|---|
| On time | less than 6 minutes late at arrival (at departure if the train starts at the station) → the definition used by Deutsche Bahn |
| On-time share | on-time stops divided by stops that were not cancelled |
| Cancellation rate | cancelled stops divided by all planned stops |
| Average delay | mean of `delay_min` over stops that were not cancelled (early arrivals count as negative values) |

### 1.8 Scope of work

| In scope | Out of scope |
|---|---|
| Regional trains and S-Bahn (BEG's responsibility) | Long-distance trains (ICE/IC) → used only as a benchmark in Q6 (BEG does not contract them) |
| Six stations: Regensburg, München, Nürnberg, Hof, Landshut, Ingolstadt (all Hbf) | Stops between these stations |
| 20 Oct - 6 Nov 2026 | Long-term trends, seasonal effects |
| Delays and cancellations as reported by the API | Causes of delays (no reliable cause data), passenger numbers |

| SOW component | Content |
|---|---|
| Deliverables | the seven deliverables below |
| Milestones | 1. data collected and frozen, 2. data cleaned and verified, 3. all guiding questions answered, 4. dashboard published, 5. case study published |
| Reports | status in the changelog (`docs/CHANGELOG.md`) and in the task list of this document |

### 1.9 Deliverables

1. A clear statement of the business task (section 1.5)
2. A description of all data sources used (section 2)
3. Documentation of any cleaning or manipulation of data (section 3, `docs/CHANGELOG.md`)
4. A summary of the analysis (section 4)
5. Supporting visualisations and key findings (section 5, Tableau dashboard)
6. Top high-level insights based on the analysis (section 6)
7. A list of additional deliverables that would help further exploration (section 6)

---

## 2. Prepare

### 2.1 Data source

| Item | Description |
|---|---|
| Source | Deutsche Bahn, **DB Timetables API v1**, via the DB API Marketplace (free plan, registration required) |
| Endpoints used | `/plan` (planned stops for one hour) and `/fchg` (all known real-time changes for a station) |
| Format | XML, one `<s>` element per stop of a train at a station |
| Stations | Regensburg, München, Nürnberg, Hof, Landshut, Ingolstadt (all Hbf), identified by their EVA numbers |
| Collection | own Python collector (`ingestion/collector.py`), run hourly via Windows Task Scheduler |
| Period | 20 Oct - 6 Nov 2026 (data frozen) |
| Licence | Creative Commons Attribution 4.0 (CC BY 4.0), attribution: Deutsche Bahn AG |

**Why did the data have to be collected?** The API only returns the current day and the next hours. It keeps no history, so a dataset for a period can only be built by collecting it continuously.

### 2.2 How the data is stored and organised

DB Timetables API (XML) → collector.py (Python) → staging (raw, PostgreSQL 17 in Docker) → core (cleaned view, PostgreSQL 17 in Docker) → analysis

| Layer | Object | Organisation |
|---|---|---|
| Raw samples | `samples/*.xml` | unchanged API responses used to explore the structure |
| Staging | `staging.stg_plan`, `staging.stg_changes` | one row per stop and station, values as delivered (text), full original XML kept in `raw_xml` |
| Staging | `staging.ingestion_log` | one row per API request (status, rows, errors) |
| Core | `core.stops` (view) | one row per stop: planned vs. actual times, delays, cancellation, flags |
| Mart | `mart.stations`, `mart.stops`, `mart.segments`, `mart.network` (views) | data prepared for the dashboard (the last three are exported as CSV files to `exports/`) |

The data is structured and in long format (one row per observation). Plan and real-time changes are linked by the key `(station, stop_id)`, a relational design with a composite primary key. All fields are documented in `docs/DATA_DICTIONARY.md`.

### 2.3 Size and completeness

| Measure | Value |
|---|---|
| Calendar days | 18 (20 Oct - 6 Nov 2026), data on 17 days (1 Nov missing) |
| Stops | 25,106 |
| Trips | 20,132 |
| Collector runs / API requests | 369 / 8,852 |
| Failed requests | 1 (0.01 %) → a network timeout, logged and skipped |
| Stops with real-time data | 97.3 % |

Coverage was uneven, because the collector ran on a laptop that was not always switched on:

| Coverage | Days |
|---|---|
| near-complete (20-24 hours) | 22, 23, 24, 25 Oct (Thu–Sun) |
| partial (7-17 hours) | 21, 26-30 Oct, 2-5 Nov |
| very low (<= 5 hours) | 20 Oct (start), 31 Oct, 6 Nov (end) |
| none | 1 Nov |

| Time of day | Days with data |
|---|---|
| 5–8 a.m. (morning peak) | 4 |
| 9-11 a.m. | 8-9 |
| 12 p.m. - 6 p.m. | 12-15 |
| 7-11 p.m. | 7-14 |

### 2.4 Credibility: does the data ROCCC?

| Criterion | Assessment | Rating |
|---|---|---|
| Reliable | operational data from Deutsche Bahn's own systems, the same source as station displays. Limitation: the stored delay is the last value seen, up to one hour before the train passed. | Mostly met |
| Original | first-party data, collected directly from the API; the raw XML of every stop is kept | Met |
| Comprehensive | covers six major stations, not the whole network; collection gaps (see 2.3); no reliable delay causes | Partly met |
| Current | October/November 2026; reflects current operations including ongoing construction work | Met for this period |
| Cited | official API of Deutsche Bahn AG, documented in the DB API Marketplace, licence CC BY 4.0 | Met |

### 2.5 Bias

- Sampling bias (time): the morning peak (5-8 a.m.) is covered on only 4 days, afternoons on 15. Results by time of day are weighted towards the afternoon.
- Sampling bias (days): only three weekend days, one of them partial. Weekday comparisons are limited.
- Selection of stations: six large hubs. Smaller stations, where delays may behave differently, are not included.
- Seasonal effects: 18 autumn days. Construction work (e.g. at Hof) and weather in this period influence the results.

**How the bias is handled.** Every result in the analysis is reported together with its number of stops (`n`), time-of-day results are checked against the four near-complete days, and conclusions are limited to the observed period.

### 2.6 Licensing, privacy, security, accessibility

| Aspect | How it is addressed |
|---|---|
| Licensing | CC BY 4.0: free use with attribution to Deutsche Bahn AG |
| Privacy | no personal data: only timetables, trains and stations |
| Security | API keys and database password are stored in `.env`, which is excluded from version control (`.gitignore`); a template without secrets is provided (`.env.example`) |
| Accessibility | code, SQL and documentation are public on GitHub; the prepared dashboard data is published as CSV files in `exports/` and within the Tableau Public workbook (with attribution to Deutsche Bahn AG); the raw staging data is not published, but can be re-collected with the same scripts |
| Backup | full database dump (`pg_dump`) stored locally, so the frozen dataset cannot be lost |

### 2.7 Data integrity checks during collection

| Check | Result |
|---|---|
| Duplicates | prevented by design: primary key `(eva, stop_id)` plus upsert, so re-fetching a stop updates it instead of duplicating it |
| Failed requests | logged in `staging.ingestion_log`: 1 of 8,852 |
| Correct stations | station names returned by the API compared with the expected names; one wrong EVA number found and fixed (8000183 is Ingolstadt, not Hof) |
| Structure | all attributes inventoried with `inspect_xml.py` before the tables were designed |

### 2.8 Known problems with the data

| Problem | Effect | Handling |
|---|---|---|
| Collection gaps | fewer observations on some days and hours | report `n`, compare with near-complete days |
| Snapshot of delays | final delay may differ from the last value seen | documented as a limitation |
| Partial cancellations | a stop counts as cancelled if arrival or departure is cancelled | definition stated in section 1.7 |
| Daylight saving time (25 Oct) | times are stored without time zone; a few night trains around 2-3 a.m. may show delays off by 60 minutes | negligible share of stops; documented |
| Station names in routes vary (e.g. "München Hbf Gl.27-36") | origin/destination names are not fully standardised | cleaned where needed in the analysis |
| Construction at Hof | lines RB97, RE31, RE2 are 100 % cancelled at Hof | analysed separately in Q5 |

---

## 3. Process

### 3.1 Tools and why

| Tool | Used for | Why |
|---|---|---|
| Python (requests, psycopg) | calling the API, parsing XML, loading the database | the API returns XML that must be fetched hourly and parsed, which spreadsheets cannot do |
| PostgreSQL 17 | storing, cleaning, verifying and analysing the data | 25,000+ rows from two linked sources: a relational database with SQL handles this volume, joins and reproducible cleaning far better than a spreadsheet |
| Docker | running PostgreSQL locally | the same database setup can be recreated anywhere with one command |
| Git / GitHub | version control and documentation | every change to code and cleaning logic is traceable |

### 3.2 Cleaning approach

The original data is never overwritten. Cleaning happens in layers:

- Staging (`sql/01_staging.sql`): raw values exactly as delivered by the API, including the full original XML of every stop.
- Core (`sql/02_core.sql`): a cleaned view on top of staging. Because it is a view, every cleaning step is a documented SQL expression and can be changed and re-run at any time without touching the raw data.

### 3.3 Cleaning steps

|   | Problem in the raw data | Dirty data type | Cleaning step |
|---|---|---|---|
| 1 | the same stop is fetched in several hourly runs | duplicate | primary key `(eva, stop_id)` + upsert: a repeated stop updates the existing row |
| 2 | times stored as text like `2610191512` | mismatched data type | converted to timestamps with `to_timestamp(…, 'YYMMDDHH24MI')` |
| 3 | cryptic column names (`arr_pt`, `dp_cp`) | misleading variable labels | renamed to readable names (`planned_arrival_at`, `actual_platform`) |
| 4 | plan and real-time changes delivered separately | data in two tables | merged with a `LEFT JOIN` on the key, so stops without changes are kept |
| 5 | no real-time data for some stops (2.7 %) | incomplete | assumed to run as planned; marked with `has_change_record` |
| 6 | long-distance trains have no line name | incomplete | line built from category + number, e.g. `ICE 1003` |
| 7 | line and platform stored twice (arrival + departure) | inconsistent | combined into one value per stop with `COALESCE` |
| 8 | one station loaded under a wrong EVA number (Hof) | incorrect | EVA number corrected in the collector; the affected rows belong to Ingolstadt and were kept as a sixth station |
| 9 | implausible delays (early departures, daylight saving night) | incorrect / outliers | kept, but flagged with `is_suspect_delay` and excluded from delay metrics |

New fields calculated during cleaning: delay in minutes, on-time flag, delay category, cancellation flag, service type, trip ID, stop index, origin and destination. All fields are documented in `docs/DATA_DICTIONARY.md`.

### 3.4 Verification

The cleaned data was checked against the verification checklist with SQL queries:

| Check | Result |
|---|---|
| Recheck against the original data | 25,106 rows in staging = 25,106 rows in core: nothing lost or added |
| Duplicates | 0 |
| Null data in required fields (time, station, category, line, trip, delay) | 0 |
| Consistent strings | exactly 6 station names, one per station |
| Mismatched data types | all times converted without error |
| Business logic: one journey passes each station at most once | 0 violations |
| Categories | all 21 train categories mapped to the correct service type |

### 3.5 Outliers

Delay distribution of all non-cancelled stops (24,475):

| Median | 90th percentile | 99th percentile | Maximum |
|---|---|---|---|
| 1 min | 11 min | 48 min | 327 min |

- Large delays (24 stops over 2 hours) were checked and are consistent along the route, e.g. Nightjets about 4 hours late at Nürnberg, Ingolstadt and München on 23 Oct. They are real and kept.
- Early stops (13 stops more than 10 minutes early) fall into three groups: artefacts of the daylight saving time change, implausibly early trains (up to 94 minutes), and trains arriving slightly early at their final stop. Only the first two groups are flagged as suspect.
- In total, 10 stops are flagged as suspect (8 long-distance, 2 regional). The effect on the regional analysis is negligible.
- Because a few extreme values pull the average up, results are reported with the median as well as the average.

### 3.6 Documentation

| Where | What |
|---|---|
| `docs/CHANGELOG.md` | chronological list of all changes to collection and cleaning (with reasons) |
| `docs/DATA_DICTIONARY.md` | every field: source, meaning, type |
| SQL comments | each cleaning step is explained directly in `02_core.sql` |
| Git history | every change to code, with date and description |

---

## 4. Analyze

### 4.1 How the analysis is organised

All queries are in `sql/03_analysis.sql`, one per guiding question.

- **Analysis base.** A temporary table with all regional and S-Bahn stops (BEG scope) without suspect delays: 20,573 stops. The scope is defined once and reused by every query.
- **Metrics.** On-time share and delays count only stops that were not cancelled. Cancellations are reported separately (definitions in section 1.7).
- **Sample size.** Every result shows its number of stops (`n`). Lines with fewer than 20 stops are left out of rankings.
- **Techniques.** Aggregation with `GROUP BY`, conditional counts with `FILTER`, median with `percentile_cont`, and window functions: `RANK()` for rankings within groups and `LAG()` to compare consecutive stations of the same journey.
- **Overall results.** In the BEG scope, 82.4 % of the stops that ran were on time (Deutsche Bahn definition, cancelled stops excluded), 2.4 % of all planned stops were cancelled, and the average delay was 3.4 min. Measured against all planned stops, including cancelled ones, about 80 % were on time (dashboard view).

### 4.2 Q1: Punctuality per station

| Station | n | On time | Cancelled | Avg delay | Median delay |
|---|---|---|---|---|---|
| Ingolstadt Hbf | 2,004 | 75.6 % | 1.7 % | 4.3 min | 2 min |
| München Hbf | 2,777 | 76.0 % | 1.6 % | 4.2 min | 1 min |
| Landshut Hbf | 1,874 | 78.8 % | 0.7 % | 4.0 min | 2 min |
| Hof Hbf | 2,497 | 82.9 % | 9.7 % | 3.3 min | 1 min |
| Nürnberg Hbf | 8,673 | 85.5 % | 1.5 % | 3.0 min | 1 min |
| Regensburg Hbf | 2,748 | 85.6 % | 1.5 % | 2.6 min | 1 min |

**Finding.** München and Ingolstadt are the least punctual stations, Regensburg and Nürnberg the most punctual. Nürnberg's value is raised by the S-Bahn, which makes up almost half of its stops (4,257 of 8,673) and is very punctual. Hof stands out with by far the highest cancellation rate (see Q5).

### 4.3 Q2: Lines and operators

Worst lines per station:

| Station | Rank 1 | Rank 2 | Rank 3 |
|---|---|---|---|
| München | **RE1** 44.5 % | RE23 60.9 % | RE96 61.8 % |
| Ingolstadt | **RE1** 50.2 % | RB14 63.2 % | RB16 72.5 % |
| Nürnberg | RE31 54.1 % | **RE1** 59.6 % | RE35 60.0 % |
| Landshut | RE23 50.0 % | RE2 65.8 % | RE25 72.7 % |
| Hof | RE38 61.3 % | RB97 64.3 % | RE2 66.4 % |
| Regensburg | RE40 71.6 % | RE23 72.2 % | RE2 74.1 % |

**Finding.** RE1 is the least punctual line at all three stations it serves (München, Ingolstadt, Nürnberg), with average delays of about 10 minutes and 5-11 % cancellations. A line that performs badly at every station points to a line-specific problem rather than a problem of one station. RE2 appears in the bottom three at three stations (Hof, Landshut, Regensburg).

Across all six stations:

| Rank | Line | n | On time | Cancelled | Avg delay |
|---|---|---|---|---|---|
| 1 | RE1 | 861 | 50.7 % | 6.9 % | 9.8 min |
| 2 | RE90 | 176 | 61.6 % | 2.3 % | 10.4 min |
| 3 | RE96 | 35 | 61.8 % | 2.9 % | 5.7 min |
| 4 | RB14 | 70 | 63.2 % | 2.9 % | 4.6 min |
| 5 | RB97 | 372 | 64.3 % | 30.6 % | 5.1 min |
| 6 | RE32 | 164 | 65.6 % | 0.6 % | 6.6 min |
| 7 | RE23 | 78 | 65.7 % | 14.1 % | 6.1 min |
| 8 | RE31 | 305 | 66.4 % | 20.0 % | 6.5 min |
| 9 | RE38 | 79 | 70.1 % | 2.5 % | 4.8 min |
| 10 | RE2 | 630 | 71.0 % | 10.2 % | 5.4 min |

**Finding.** Only two of the ten least punctual lines reach 70 %. RE1 stands out in two ways. It is on time at only every second stop, and with 861 stops it is by far the largest line in this ranking. The result is therefore robust and affects many passengers. The high cancellation rates of RB97, RE31 and RE2 come mainly from the four days at Hof (see Q5). RE96 and RB14 have fewer than 100 stops, so their position is less certain.

Operators:

| Rank | Category | n | Lines | On time | Avg delay |
|---|---|---|---|---|---|
| 1 | RE (mostly DB Regio) | 6,426 | 25 | 75.3 % | 4.7 min |
| 2 | ALX (alex) | 666 | 2 | 76.0 % | 4.5 min |
| 3 | ARV (Arverio) | 1,538 | 9 | 77.5 % | 4.1 min |
| 4 | EB (Erfurter Bahn) | 147 | 1 | 77.6 % | 4.9 min |
| 5 | RB | 2,457 | 13 | 78.6 % | 3.7 min |
| 6 | MRB (Mitteldeutsche Regiobahn) | 330 | 1 | 85.2 % | 3.5 min |
| 7 | BRB (Bayerische Regiobahn) | 442 | 2 | 85.5 % | 2.4 min |
| 8 | ag (agilis) | 3,929 | 10 | 85.6 % | 2.6 min |
| 9 | S (S-Bahn) | 4,257 | 6 | 93.1 % | 1.6 min |
| 10 | OPB (oberpfalzbahn) | 363 | 1 | 95.6 % | 1.3 min |

**Finding.** The spread between operators is large (75 % to 96 %). Operators with one or two lines depend strongly on the conditions of those lines, so this ranking must not be read as a direct quality comparison of operators (see Q4: infrastructure matters).

### 4.4 Q3: Time of day and weekday

| Hours | On time | Days with data |
|---|---|---|
| 5-6 a.m. | 84-90 % | 4 |
| 7-11 a.m. | 79-81 % | 4-9 |
| 12 p.m. - 8 p.m. | 81-85 % | 12-15 |
| 9-11 p.m. | 75-81 % | 7-10 |

**Finding.** Punctuality is best early in the morning, drops in the morning peak, is stable in the afternoon and is lowest late in the evening (11 p.m.: 75.4 %). This fits the pattern of delays building up over the day. The morning hours are covered on only four days (sampling bias, see 2.5), so this result is an indication, not a proof.

By weekday, Wednesday is the weakest day (78.0 % vs. 82-85 % on the other days). With only one to three days per weekday, this difference may be caused by single disrupted days and is not reliable.

### 4.5 Q4: Where delays build up

Some journeys pass several of the six stations. `LAG()` compares the delay of one journey at a station with its delay at the previous station:

| Segment | Journeys | Delay before | Delay after | Change |
|---|---|---|---|---|
| Hof → Nürnberg | 66 | 1.9 min | 12.0 min | +10.1 min |
| Nürnberg → Hof | 91 | 2.6 min | 10.3 min | +7.7 min |
| Regensburg → Hof | 53 | 6.9 min | 11.9 min | +5.0 min |
| Regensburg → Nürnberg | 225 | 2.3 min | 5.7 min | +3.4 min |
| München → Landshut | 334 | 1.3 min | 4.6 min | +3.3 min |
| Nürnberg → Regensburg | 218 | 2.0 min | 5.0 min | +3.0 min |
| München → Ingolstadt | 324 | 4.3 min | 7.2 min | +2.8 min |
| … | | | | |
| Ingolstadt → Nürnberg | 172 | 8.0 min | 7.8 min | -0.2 min |
| Landshut → Regensburg | 388 | 5.3 min | 4.3 min | -1.1 min |

→ The network map in the dashborad combines both directions of a section, weighted by the number of journeys.

**Finding.** The corridor Nürnberg - Hof is the clear hotspot: journeys lose 8-10 minutes in both directions. Together with the cancellations on lines to Hof (Q5) and RE31 as the worst line at Nürnberg, this points to a section of track rather than to one operator. Leaving München also costs time in both directions (+3.3 and +2.8 min), which suggests congestion in the München hub. On Landshut → Regensburg, journeys recover time, so the timetable has buffer there. 

The timing coincides with construction work announced by Deutsche Bahn in north-eastern Bavaria (closure Marktredwitz - Kirchenlaibach, 19 - 23 October 2026). Whether this closure caused all cancellations at Hof could not be confirmed from the data.

The change per segment includes all intermediate stops and dwell times. It shows where delays grow, not why.

### 4.6 Q5: Cancellations

Regional rail has a cancellation rate of 2.9 %, the S-Bahn 0.8 %. The highest rates per line are all at Hof:

| Line at Hof | Cancelled 20-23 Oct | Cancelled 24 Oct - 6 Nov |
|---|---|---|
| RB97 | 104 of 123 (85 %) | 10 of 249 (4 %) |
| RE31 | 52 of 52 (100 %) | 2 of 124 (2 %) |
| RE2 | 52 of 52 (100 %) | 7 of 117 (6 %) |

**Finding.** The cancellations at Hof are systematic but temporary. Three lines were (almost) completely cancelled for four days and ran nearly normally afterwards. This points to a planned closure, not to unreliable operations. Outside Hof, RE1 has the highest cancellation rates (Nürnberg 11.3 %, Ingolstadt 5.4 %, München 4.9 %).

### 4.7 Q6: Regional rail compared with long-distance and S-Bahn

| Service type | n | On time | Cancelled | Avg delay | Median | 90th percentile |
|---|---|---|---|---|---|---|
| Long distance | 4,515 | 64.8 % | 2.9 % | 9.0 min | 2 min | 26 min |
| Regional | 16,316 | 79.5 % | 2.9 % | 3.8 min | 1 min | 10 min |
| S-Bahn | 4,257 | 93.1 % | 0.8 % | 1.6 min | 1 min | 4 min |

**Finding.** Regional rail is clearly more punctual than long-distance and clearly less punctual than the S-Bahn. The 90th percentile shows the difference best. One in ten long-distance stops is at least 26 minutes late, compared with 10 minutes for regional trains and 4 for the S-Bahn.

### 4.8 Surprises

- Nürnberg looks like one of the most punctual stations, but only because of its S-Bahn share.
- The high cancellation rate at Hof is not a permanent problem, but a four-day closure.
- Punctuality is lowest late in the evening, not in the morning peak (with the caveat of fewer morning days).
- One line (RE1) dominates the bottom of the ranking at three different stations.

### 4.9 Summary: how the findings answer the business task

| Question by the business task | Answer from the analysis |
|---|---|
| Where does punctuality fall short? | München and Ingolstadt (~ 76 %). The corridor Nürnberg - Hof, where delays grow most |
| When? | Late evening. Delays build up over the day |
| On which lines? | RE1 (worst at three stations), RE31, RE2 |
| Operator or infrastructure? | RE1 points to a line-specific problem. Nürnberg - Hof and the München hub point to infrastructure. Hof cancellations were a temporary closure |

---

## 5. Share

### 5.1 Dashboard

**[Regional Rail Punctuality in Bavaria](https://public.tableau.com/app/profile/philipp.sch.nfeld/viz/bahn_punctuality_dashboard/Whereandwhichlines)** (Tableau Public)

The dashboard is built from the mart views in `sql/04_mart.sql`, exported as CSV files to `exports/`.

### 5.2 Audience and approach

The primary audience is BEG management, which needs the main findings first and has little time. The dashboard therefore follows three rules:

- **One message per chart.** Every title states the finding instead of describing the chart.
- **Overview first, details second.** The first dashboard answers where and on which lines, the second when and why. A button links the two.
- **Plain language.** Definitions appear where they are needed.

### 5.3 What the dashboard shows

| Dashboard | Chart | Guiding question | Message |
|---|---|---|---|
| Regional Rail Punctuality in Bavaria | Stacked bar | overall result | 80 of 100 planned stops were on time |
| | Network map | Q1, Q4 | Trains lose almost 9 minutes between Hof and Nürnberg; München, Ingolstadt and Landshut are below average |
| | Line scorecard | Q2 | RE1 is on time at only half of its stops |
| | Service types | Q6 | Regional trains beat long-distance trains but trail the S-Bahn |
| When and Why Service Suffers | Line chart by hour | Q3 | Punctuality is at its lowest late in the evening |
| | Bars by day | Q5 | A four-day closure caused almost all cancellations at Hof |

### 5.4 Design decisions

| Decision | Reason |
|---|---|
| One colour logic on both dashboards: purple = meets the target or above average, orange = misses it, grey = benchmark | the reader learns the meaning once and can read every chart with it |
| Interactive target slider in the line scorecard | BEG can set its own punctuality target and see at once which lines miss it |
| Station filter | quality managers can look at the lines of a single station |
| Schematic network map with sections between the six stations | shows where delays build up, which a table cannot show at a glance |
| Values labelled directly on the bars | exact numbers without reading an axis |
| Long-distance trains shown in grey | they are not contracted by BEG and serve only as a benchmark |

### 5.5 Accessibility

- Colours avoid the red-green combination and differ in brightness, so they can also be distinguished with the common forms of colour blindness.
- Every value is available as a label or in a tooltip, not only as a colour or length.
- English number and date formats, short sentences, definitions next to the figures.
- The dashboard runs in any web browser without installing software.

### 5.6 Five-second test

The dashboard was shown to three persons for five seconds each. Afterwards they were asked what they remembered. Result, two of three named RE1 or the Hof - Nürnberg section as the main problem.

### 5.7 Answers to the guiding questions of the roadmap

| Question | Answer |
|---|---|
| Was the business question answered? | Yes: where (München, Ingolstadt, the corridor Nürnberg - Hof), when (late evening) and on which lines (RE1, followed by RE90 and RE96) punctuality falls short |
| What story does the data tell? | Regional rail in Bavaria is mostly punctual, but the problems are concentrated on a few lines and sections. That makes targeted measures possible |
| Who is the audience and how is it addressed? | BEG management through findings in the titles, the quality team through filters, the target slider and tooltips |
| Is the presentation accessible? | Yes, see 5.5 |

---
 
## 6. Act

### 6.1 Conclusion

Regional rail at the six stations is mostly punctual: 82 % of the stops that ran were on time. The problems are not spread evenly, but concentrated:

1. **One line:** RE1 is the least punctual line at all three stations it serves and is on time at only half of its stops.
2. **One corridor:** between Nürnberg and Hof, journeys lose almost 9 minutes, in both directions.
3. **One time of day:** punctuality is lowest late in the evening, when delays from the whole day have built up.
4. **One temporary event:** the cancellations at Hof were limited to four days and do not point to a permanent problem.

Because the problems are concentrated, BEG can address them in a targeted way instead of across the whole network.

### 6.2 The central decision: how should BEG use punctuality data?

The real-world gap (section 1.1) is that punctuality sits outside BEG's main steering instrument. Three options:

| Option | Advantages | Disadvantages |
|---|---|---|
| A. Include punctuality directly in bonuses and penalties | strong financial incentive | punishes operators for infrastructure problems, the reason BEG left punctuality out |
| B. Monitor punctuality separately and use it in quality talks | quick to introduce, fair, no contract changes needed | no direct financial incentive |
| C. First separate the causes (operator or infrastructure), then include only operator-caused delays in the incentives | fair and with an incentive | requires Deutsche Bahn's internal cause data and contract changes |

**Recommendation.** Start with option B now, using this dashboard as a prototype, and prepare option C in the medium term. The analysis shows that some problems are line-specific (RE1) and others are tied to sections (Nürnberg - Hof). Treating both the same way, as option A does, would be unfair.

### 6.3 Recommendations

Recommendations marked data-based follow directly from the analysis. Recommendations marked hypothesis are plausible explanations that the data cannot prove, because it contains no causes.

|   | Problem | Recommendation | Basis |
|---|---|---|---|
| 1 | RE1 is the least punctual line at three stations | Put RE1 first on the agenda of the next quality talks with its operator and ask for the operator's delay causes | data-based |
| 2 | Delays grow by almost 9 minutes between Nürnberg and Hof | Raise the corridor with the infrastructure manager and check whether construction work or capacity limits are the cause | data-based (where), hypothesis (why) |
| 3 | Leaving München costs time in both directions | Monitor the München hub, congestion at the hub is a possible cause | hypothesis |
| 4 | Punctuality is lowest late in the evening | Check whether the timetable has too little buffer to absorb delays built up during the day | hypothesis |
| 5 | Punctuality is not visible in BEG's steering | Continue the data collection permanently and publish the dashboard regularly, alongside the quality ranking | data-based |

### 6.4 Limitations

- 18 days in autumn, with collection gaps (section 2.3): the results describe this period, not a whole year.
- The morning peak is covered on only four days (section 2.5).
- Six large stations only: stops in between and smaller stations are not included.
- The data contains no delay causes, so the distinction between operator and infrastructure is an indication, not a proof.

### 6.5 Next steps

| What | Who | When |
|---|---|---|
| Discuss RE1 and the corridor Nürnberg - Hof | BEG quality management, operator, infrastructure manager | next regular quality talks |
| Run the collector permanently on a server instead of a laptop | BEG data team | within 3 months |
| Extend the collection to more stations | BEG data team | within 6 months |
| Request delay causes from Deutsche Bahn to separate operator and infrastructure causes (prerequisite for option C) | BEG management | within 6 months |
| Repeat the analysis after one year and compare seasons | BEG data team | after 12 months |

### 6.6 Additional data that would expand the findings

| Data | What it would add |
|---|---|
| A full year of collection | seasonal effects, reliable weekday and morning results |
| Delay causes (Deutsche Bahn internal data) | clear separation of operator and infrastructure causes |
| Construction calendar of the infrastructure manager | explains temporary effects such as the Hof cancellations |
| Passenger numbers per line | weights delays by the number of affected passengers |
| Weather data | separates weather-related disruptions from structural problems |
| All intermediate stops | locates delays more precisely within a section |

---

## Sources

- Bayerisches Staatsministerium für Wohnen, Bau und Verkehr: [Schienenpersonennahverkehr](https://stmb.bayern.de/vum/schiene/nahverkehr/index.php)
- Railway PRO: [BEG: Service quality of regional trains in Bavaria settles at pre-Corona level](https://railwaypro.com/wp/?p=123538)
- Deutsche Bahn: [DB API Marketplace – Timetables API](https://developers.deutschebahn.com/db-api-marketplace/apis/product/timetables)
