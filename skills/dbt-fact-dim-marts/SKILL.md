---
name: dbt-fact-dim-marts
description: Build dimension and fact tables (star schema) in dbt on ClickHouse from staging models (Step 4 of platform onboarding). Use whenever the user wants to split staged data into dim_ and fact_ tables, design the grain of a fact, add or reuse shared dimensions like dim_date or dim_channel, make facts incremental, or fix duplicate, orphaned or stale rows in marts. Use it even when they just say "build the marts", "model the data" or "create the fact table".
---

# dbt fact and dimension marts

Turns `staging.stg_*` into `marts.dim_*` and `marts.fact_*`. Cube reads `marts` only, so everything here must be clean, tested and tenant-safe.

Project: `predicta_dbt/` (see `README.md`). Reference implementation: `models/marts/shared/` and `models/marts/ga4/`.

## Decide first, write second

1. **Declare the grain in one sentence per fact** ("one row per session"). Write it in the model's header comment and YAML description. Build at the grain the data supports; if the raw data is already aggregated you cannot build finer facts.
2. **Classify each dimension.**
   - Global reference (date, device, channel): no `tenant_id`.
   - Tenant-owned (page, campaign, product): carries `tenant_id`; surrogate key hashes `tenant_id` plus the natural key.
   - Reuse existing shared dims (`dim_date`, `dim_tenant`, `dim_channel`) before creating anything. Check `models/marts/shared/` and other platforms' marts.
3. Small attributes that only describe one fact may stay on the fact as degenerate columns (source, medium). Wide facts are cheap in ClickHouse; do not create a dimension for every column.

## Steps

1. **Dimensions** (`materialized='table'`, `order_by` on the key; tenant-owned dims lead with `tenant_id`). Key = `dbt_utils.generate_surrogate_key([...])`. Always provide an "unknown"/"Unassigned" member so facts cannot be orphaned.
2. **Facts** (`materialized='incremental'`, `incremental_strategy='delete_insert'`, `unique_key='<single_key>'`):
   - `unique_key` is ONE surrogate column. A list does not work with this adapter.
   - `order_by` starts with `tenant_id`; `partition_by='toYYYYMM(<date>)'`.
   - Derive dates only via `{{ to_reporting_date('col') }}`; never hard-code a timezone.
   - Compute dimension keys with the same hash recipe the dimension uses (identical expressions, identical defaults).
   - Filter incrementals with `{{ incremental_watermark('<alias>') }}` (3-day lookback by default).
   - Facts that aggregate (sessions, orders with lines): find the keys touched by new rows, then re-aggregate ALL source rows for those keys. Aggregating only the new rows overwrites a long-lived entity with a partial total.
   - LEFT JOINs: ClickHouse returns empty strings, not NULLs, for misses. Guard with `coalesce(nullIf(col, ''), 'Unassigned')`.
3. **YAML** for every model: business-language descriptions, `unique` and `not_null` on keys, `tenant_id` `not_null` + `dbt_utils.not_empty_string`, and a `relationships` test from every fact key to its dimension.
4. **Singular tests**: fact row count equals staging row count; summed child counts equal parent counts (e.g. session events vs event rows).
5. Add `post_hook="{{ apply_tenant_row_policy() }}"` to tenant-owned marts. It is a no-op until the row-policy design is decided; do not enable it unprompted.

## Gate (all must pass before Step 5, Cube)

- `dbt build --select tag:shared tag:<platform>` passes, tests included.
- No orphaned keys (relationships tests green, including the Unassigned path).
- One row traced by hand from raw to staging to fact; values match.
- Second run changes nothing (compare counts and a key hash before and after).
- Late-arriving test: insert one new event into an existing entity and one new entity; after a build the existing entity's totals are correct and nothing is duplicated.
- `dim_date` and fact dates use the one project timezone (`var('reporting_timezone')`).
- `cube_user` can SELECT from `marts` and nothing else.

## Known behaviour to design around

- Incremental models never remove rows whose source was deleted. The reconciliation test will fail; the fix is `--full-refresh` (Prefect parameter `full_refresh=true`), not a patch.
- `delete_insert` uses lightweight DELETE mutations. Keep the lookback small, run builds off-peak, and keep `threads` at 2 to 4.
- Prefer append or small-window delete_insert over row updates; never design around frequent UPDATEs.
- `table` rebuilds swap the table. Row policies or grants attached to the old table must be re-applied; test after every build once policies are on.
- Prod (2 shards x 2 replicas) needs replicated engines and a distributed-table decision. It is untested; treat the `prod` target as a draft.

## Stop and report instead of guessing when

- The grain is ambiguous or the source rows cannot support it.
- A dimension would need to be tenant-owned in one platform and global in another.
- A relationships test fails: trace the orphan to its step before changing any model.
- `reporting_timezone` is still undecided and the platform needs tenant-local dates.

## Do not

- Define metrics, joins for dashboards, or pre-aggregations here. That is Cube.
- Run dbt per tenant.
- Read raw or S3 directly; facts read staging via `ref()`.
- Drop, truncate or overwrite tables without confirming.
