---
name: dbt-staging-models
description: Build the dbt staging model for one platform's raw ClickHouse table (Step 3 of platform onboarding). Use whenever raw data has been landed in ClickHouse and needs to be unnested, typed, renamed and deduplicated before dimensional modelling, or when the user mentions staging models, stg_ models, cleaning raw tables, dbt sources, or dedupe. Use it even if they only say "transform the raw table" or "set up dbt for <platform>".
---

# dbt staging models

Turns `raw.raw_<platform>_*` into `staging.stg_<platform>__<entity>`: one model per raw table, typed, renamed, deduplicated, tenant-tagged. Nothing else. Joins, business logic and aggregation belong in marts.

Project: `predicta_dbt/` (see `README.md`). Reference implementation: `models/staging/ga4/`.

## Before writing anything

1. Inspect, do not assume. Run `DESCRIBE TABLE raw.<table>` and `SELECT * ... LIMIT 20` on real rows. Read `connectors/<platform>.md`. Raw shapes in decks and docs are illustrative; the table is the truth.
2. Confirm the grain of the raw table (event rows, or aggregated report rows). If it is aggregated, say so and stop to confirm; the marts design depends on it.
3. Check versions: `dbt --version` and the adapter version match `orchestration/requirements.txt`.

## Steps

1. **Source.** Add the table to `models/staging/<platform>/_<platform>__sources.yml` under source `raw` with `loaded_at_field: _loaded_at` and a 26 h `warn_after` freshness rule.
2. **Model** `stg_<platform>__<entity>.sql`, tagged `<platform>` (the folder config does this). Use CTEs in this order: `source`, `typed`, `keyed`, final dedupe.
   - Cast types; convert timestamps explicitly (state the unit and timezone you assumed in a comment).
   - Unnest arrays and JSON with `arrayJoin` / `JSONExtract*`. Keep nested fields you will need later.
   - Normalise categorical text with `lower()` and `coalesce(nullIf(x, ''), '<default>')`. In ClickHouse empty strings, not NULLs, are the usual "missing".
   - Keep `tenant_id` and `_loaded_at` untouched.
   - Build a deterministic key with `dbt_utils.generate_surrogate_key([...])` including `tenant_id`.
   - Dedupe: `order by _loaded_at desc limit 1 by <key>`. Re-landed files and platform reprocessing both create duplicates.
3. **Materialisation.** `view` for the PoC. Move to incremental only when builds get slow, using `macros/incremental_watermark.sql`.
4. **YAML** `_stg_<platform>__models.yml`: a real business-language description for the model and every column you keep, plus tests:
   - key: `not_null`, `unique`
   - `tenant_id`: `not_null` AND `dbt_utils.not_empty_string` (ClickHouse Strings are never NULL, so `not_null` alone passes empty tenants)
   - `accepted_values` on any enum you rely on
5. **Singular test** `tests/assert_stg_<platform>_<entity>_matches_raw.sql`: per tenant, staging count must equal the count of distinct keys in raw. Any difference is an unexplained drop.

## Gate (all must pass before Step 4)

- `dbt build --select stg_<platform>__<entity>` passes, including tests.
- Row-count reconciliation test passes; any dropped row is explained in the model comments.
- Five real fields spot-checked against a raw sample by hand (timestamps, nested values, categories).
- Running the build twice changes nothing.
- Descriptions read as business questions, not column restatements.

## Stop and report instead of guessing when

- The raw shape differs from `connectors/<platform>.md` or from what the model assumes.
- Timestamps have no documented unit or timezone.
- `tenant_id` is empty on any row (report the count and the source file; do not filter silently).
- Dedupe would drop rows that differ in meaningful columns, not just `_loaded_at`.

## Do not

- Join to dimensions, aggregate, or compute KPIs here.
- Hard-code a timezone; date conversion happens in marts via `to_reporting_date()`.
- Read S3 or MinIO from dbt. Loading raw is Prefect's job (Step 2).
- Delete or overwrite anything without confirming first.
