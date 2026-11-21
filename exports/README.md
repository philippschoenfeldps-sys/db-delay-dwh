# Exports

CSV files for the Tableau Public dashboard, exported from the mart views in `sql/04_mart.sql` (Tableau Public cannot connect to PostgreSQL).

| File | Source view | Rows | Content |
|---|---|---|---|
| `stops.csv` | `mart.stops` | 25,088 | one row per stop, 20 Oct - 6 Nov 2026 |
| `segments.csv` | `mart.segments` | 3,420 | delay change between consecutive stations of one journey |
| `network.csv` | `mart.network` | 14 | 6 stations and 8 sections for the network map |

All columns are described in `docs/DATA_DICTIONARY.md`, section 8.

## How to re-create the files

Run from the repo root (cmd). The database must contain the data and the mart views (`sql/04_mart.sql`).

```bat
docker exec -i bahn-postgres psql -U bahn -d bahn_dwh -c "\copy (SELECT * FROM mart.stops) TO STDOUT WITH (FORMAT csv, HEADER)" > exports\stops.csv
docker exec -i bahn-postgres psql -U bahn -d bahn_dwh -c "\copy (SELECT * FROM mart.segments) TO STDOUT WITH (FORMAT csv, HEADER)" > exports\segments.csv
docker exec -i bahn-postgres psql -U bahn -d bahn_dwh -c "\copy (SELECT * FROM mart.network) TO STDOUT WITH (FORMAT csv, HEADER)" > exports\network.csv
```

Format: UTF-8, comma as separator, point as decimal separator, first row = column names. With a German system locale, set the separator to comma in Tableau under *Text File Properties*.

## Licence

Source: Deutsche Bahn AG, DB Timetables API, licensed under CC BY 4.0. The data was cleaned and prepared for this project (see `docs/CASE_STUDY.md`, section 3).

