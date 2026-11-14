# Case Study: Punctuality of Regional Rail at Six Bavarian Hubs

Google Data Analytics Professional Certificate – Capstone Project (own case study)

Author: Philipp Schönfeld
Data period: 20 Oct – 6 Nov 2026
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
 
**The real-world gap.** BEG rewards or penalises operators based on a published service quality ranking. This ranking rates only what operators control directly, such as cleanliness, passenger information, equipment and complaint handling. Punctuality and cancellations are deliberately left out and recorded in a separate system ([Railway PRO](https://railwaypro.com/wp/?p=123538).

The reason is that a delay can be caused either by the operator (e.g. staff shortages, broken train) or by the infrastructue (e.g. signal failure, track works). A punctuality figure mixes both cases. Therefore, basing bonuses or penalties on it would also punish operators for problems they cannot control.

As a result, the quality aspect that matters most to passengers sits outside BEG's main steering instrument. This project uses open real-time data to show where and when punctuality falls short, and gives hints whether a problem lies with the operator or the infrastructure. It does not replace BEG's internal, but offers an independent, fine-grained view.
 
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

The questions follow the **SMART** methodology: specific, measurable, action-oriented, relevant and time-bound (all refer to 20 Oct – 6 Nov 2026).

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

*To be completed. Guiding questions from the roadmap:*
- Where is the data located, and how is it organised?
- Are there issues with bias or credibility? Does the data **ROCCC**?
- How are licensing, privacy, security and accessibility addressed?
- How was the data's integrity verified?
- How does it help answer the question? Are there problems with the data?

---

## 3. Process

*To be completed. Guiding questions from the roadmap:*
- Which tools were chosen, and why?
- Has the data's integrity been ensured?
- Which steps were taken to clean the data, and how was it verified?
- Is the cleaning process documented (changelog)?

---

## 4. Analyze

*To be completed: one subsection per guiding question with query, result and finding. Guiding questions from the roadmap:*
- How should the data be organised for analysis? Is it properly formatted?
- What surprises, trends or relationships were found?
- How do these insights answer the business questions?

---

## 5. Share

*To be completed: link to the Tableau Public dashboard, key charts and the story they tell. Guiding questions from the roadmap:*
- Was the business question answered? What story does the data tell?
- Who is the audience, and what is the best way to communicate with them?
- Is the presentation accessible?

---
 
## 6. Act

*To be completed, following the case study interview structure: problems → solutions with alternatives (pros and cons) → conclusion → next steps (what, who, when). Guiding questions from the roadmap:*
- What is the final conclusion?
- How could BEG apply the insights, and what are the next steps?
- Is there additional data that could expand on the findings?

---

## Sources

- Bayerisches Staatsministerium für Wohnen, Bau und Verkehr: [Schienenpersonennahverkehr](https://stmb.bayern.de/vum/schiene/nahverkehr/index.php)
- Railway PRO: [BEG: Service quality of regional trains in Bavaria settles at pre-Corona level](https://railwaypro.com/wp/?p=123538)
- Deutsche Bahn: [DB API Marketplace – Timetables API](https://developers.deutschebahn.com/db-api-marketplace/apis/product/timetables)
