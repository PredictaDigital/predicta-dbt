# MinIO → ClickHouse → dbt proof of concept (GA4 report tables)

Audience: DevOps and the data team taking this to Kubernetes.
Status: working locally in Docker. **Not yet deployed to Kubernetes.**

## 1. What was done

1. Set up the local stack from the supplied package (ClickHouse 25.3 + dbt image in Docker Compose) and validated it with the package's sample data (dbt `PASS=52`, rerun identical).
2. Connected ClickHouse to the company MinIO and loaded eight `GA4_LC_*` Airbyte report streams from bucket `predicta-poc-airbyte`, prefix `airbyte_raw/`, incrementally.
3. Built dbt staging models that unpack and deduplicate the data, and fact and dimension models on top.
4. Added automated tests and verified the results, including a rerun.

## 2. Findings about the source data

| Finding | Consequence |
|---|---|
| The URL `minio.infra.predictaanalytics.io` is the **web console**. The S3 API is `https://s3.infra.predictaanalytics.io`. | `MINIO_ENDPOINT` must be the API URL. |
| Files are Airbyte raw CSVs: five columns, with the whole record in `_airbyte_data` as a JSON string. One file per sync. | Raw tables keep the JSON untouched; dbt staging unpacks it. |
| Data is **daily aggregated GA4 reports** (by source, page, device, country, item), not event-level. | Facts are daily-grain. They do not replace `fact_events` / `fact_sessions` (event-level). |
| Each sync re-pulls a rolling date window, so the same date and dimensions appear in several files (devices: 124 rows → 116 unique). | Staging keeps the latest sync per natural key (`limit 1 by`, newest `_airbyte_extracted_at`). |
| Single GA4 property in the data (`368891428`, littlecheeks.com.au). | Mapped to tenant `t_littlecheeks` via a seed. |

## 3. Data flow

```
MinIO (CSV, Airbyte)
   │  clickhouse/04_minio_load.sh   (INSERT ... SELECT FROM s3(), only new files)
   ▼
raw.ga4_lc_*            raw JSON, one row per Airbyte record, _source_file + _loaded_at
   │  dbt staging views (stg_ga4_lc__*): unpack JSON, type, map tenant, dedupe
   ▼
staging.*
   │  dbt marts: incremental facts (delete+insert by grain key), dimension tables
   ▼
marts.fact_*_daily, marts.dim_*
```

### Incremental loading
- **Raw:** each run reads only files whose path is not yet in `raw.<table>._source_file`. Re-running adds 0 rows (verified).
- **Marts:** facts are `incremental` / `delete_insert` on a surrogate grain key, filtered by the `_loaded_at` watermark with a 3-day lookback (existing macro `incremental_watermark`). A revised value in a newer sync replaces the old row.

## 4. Eight source tables loaded

website_overview, daily_active_users, traffic_sources, traffic_acquisition_session_source_medium_report, pages, devices, locations, ecommerce_purchases_item_name_report.
Row counts after first load: 36, 36, 89, 82, 1095, 124, 835, 265.

## 5. Fact and dimension design

| Fact (grain: tenant × date ×) | Dimensions |
|---|---|
| `fact_site_daily` (nothing further) | dim_date, dim_tenant |
| `fact_traffic_daily` (source, medium) | dim_channel (via `channel_mapping` seed) |
| `fact_page_daily` (page path) | dim_page |
| `fact_device_daily` (device category, OS, browser) | dim_device |
| `fact_location_daily` (country, region, city) | dim_location (new, global) |
| `fact_item_daily` (item name) | dim_item (new, per tenant) |

Design choices:
- `dim_page` and `dim_device` were **extended** to also read the report staging models, so one conformed dimension serves both event-level and report-level facts.
- Ratios (bounce rate, engagement) are not additive. They are passed through at their natural grain, or re-weighted (page bounce rate by page views) when rolled up.
- `fact_traffic_daily` combines two reports (traffic sources + acquisition) with a union-and-sum, which avoids a nullable full join.
- OS and browser are degenerate columns on the device fact rather than extra dimensions.

## 6. Test results

| Check | Result |
|---|---|
| `dbt build --select tag:shared tag:ga4 tag:ga4_reports` | **PASS=136, WARN=0, ERROR=0** |
| Same command a second time | PASS=136 (idempotent) |
| Loader rerun | +0 rows on all 8 tables |
| Fact totals vs deduplicated staging (`assert_ga4_reports_facts_match_staging`: page views, sessions, items purchased, engaged sessions) | no differences |
| Keys: not-null and unique on every fact key | pass |
| Relationships: each fact → dim_date, dim_tenant, and its dimension | pass |
| Row counts after build | site 33, traffic 82, page 554, device 116, location 748, item 265 |
| Date range | 2026-09-06 to 2026-10-08 |
| Channel split of sessions | Direct 950, Organic Search 39, Organic Social 17, Unassigned 10, AI Assistant 7 |

Manual query checks (top pages, countries, devices, items, orphan keys) were also run by the team and looked correct.

## 7. Files changed or added in the repo

New:
- `clickhouse/04_minio_load.sh`: incremental MinIO loader
- `predicta_dbt/models/staging/ga4_reports/` (8 staging models, sources and tests yml)
- `predicta_dbt/models/marts/ga4_reports/` (6 facts, 2 dims, tests yml)
- `predicta_dbt/seeds/ga4_property_tenant.csv`, `_seeds.yml`
- `predicta_dbt/tests/assert_ga4_reports_facts_match_staging.sql`
- `docs/MINIO_GA4_POC_REPORT.md` (this file)

Changed:
- `docker-compose.yml` (passes `MINIO_*` env to the ClickHouse container)
- `.env.example` (MinIO placeholders)
- `predicta_dbt/dbt_project.yml` (tag `ga4_reports` for staging and marts)
- `predicta_dbt/models/marts/ga4/dim_page.sql`, `dim_device.sql` (union report data)
- `predicta_dbt/seeds/channel_mapping.csv` (+4 rows)
- `LOCAL_SETUP.md` (MinIO section appended)

Local only, must not be committed: `.env` (holds the real MinIO credentials).

## 8. What is NOT yet covered for Kubernetes (action items for DevOps)

1. **The loader only runs locally.** `04_minio_load.sh` runs inside the ClickHouse container. In Kubernetes it needs a scheduled owner: a Prefect task or flow (preferred, since Prefect is the only trigger per the existing design) or a CronJob using `clickhouse-client` with the same SQL. Must run before the dbt build.
2. **Secrets.** `k8s/external-secret-dbt.yaml` only provides ClickHouse credentials for dbt. Add MinIO access and secret keys in OpenBao and expose them to the loader job only (dbt never needs them). Request a **read-only** MinIO key scoped to the bucket. The key used in the POC was shared in chat and should be rotated.
3. **Prefect deployments.** `orchestration/prefect.yaml` has `dbt-ga4` running `tag:ga4` only. The new models use tag `ga4_reports`:
   - add a deployment with `platform: ga4_reports` (the flow builds `tag:{platform}`), or add the tag to the existing selection;
   - `dim_page` and `dim_device` (tag `ga4`) now depend on `stg_ga4_lc__pages` and `stg_ga4_lc__devices` (tag `ga4_reports`). Building `tag:ga4` alone on a fresh database fails, so run `ga4_reports` first or select both tags in one run. `tag:shared` models (`dim_tenant`, `dim_date`, `dim_channel`) have no dependency on report data, so `dbt-shared-daily` is unaffected.
   - the flow also takes a global concurrency lock per selector name (`dbt-<tag>`); create one for the new tag (`prefect gcl create dbt-ga4_reports --limit 1`, following the existing pattern).
4. **Image rebuild.** The dbt image bakes in models, so rebuild and push after merging. The seeds and new models must be in the image (locally they are mounted from disk).
5. **ClickHouse permissions.** `dbt_user` has `SELECT` on `raw.*`, which covers the new raw tables. The loader needs a separate user with `CREATE`, `INSERT` and `SELECT` on `raw.*` plus the `S3` grant (`GRANT S3 ON *.* TO <user>`). Locally the loader runs as `admin`.
6. **Tenant onboarding.** A new client needs its GA4 `property_id` in `seeds/ga4_property_tenant.csv` and a row in `raw.tenants`. Currently the tenant row is inserted by the loader script for `t_littlecheeks` only, and its timezone (`UTC`) is a placeholder.
7. **Row policies and tenant isolation** (`apply_row_policies`) remain disabled, as in the original package.
8. **Scale.** Only ~30 files and ~2,500 rows were loaded. The loader's "new files" check lists every file in the stream folder each run, which is fine for this size, but should be revisited (for example S3Queue or a stored file list) if streams grow to thousands of files.

## 9. Known limitations

- Ten sessions fall into "Unassigned" channel (referral and unmapped sources). The mapping seed is exact-match; generic "referral" rules were not added.
- Only 8 of ~30 `GA4_LC_*` streams are loaded. Others follow the same pattern (see `LOCAL_SETUP.md`).
- Rerunning dbt after a **new** Airbyte sync was not exercised: all current files come from two syncs. The incremental logic is written for it but unproven on real late data.
- Source freshness thresholds (48h warn / 96h error) are guesses.
