# Predicta dbt package

dbt is the "T" only. Prefect loads S3/MinIO into ClickHouse `raw`; dbt turns
`raw` into `staging` (views) and `marts` (dims and facts); Cube reads `marts`.

    raw.raw_<platform>  ->  staging.stg_*  ->  marts.dim_* / marts.fact_*  ->  Cube

## Layout

    predicta_dbt/        dbt project (models, macros, seeds, tests)
    orchestration/       Prefect flows, prefect.yaml, requirements.txt
    clickhouse/          01_bootstrap.sql, 02_grants.sql
    k8s/                 ExternalSecret, work-pool template generator
    skills/              updated dbt-staging-models, dbt-fact-dim-marts
    Dockerfile           dbt + adapter + Prefect + project, deps baked in
    docker-compose.yml   LOCAL lean setup (ClickHouse + dbt); see LOCAL_SETUP.md

## What was tested, and what was not

Tested against ClickHouse 25.3.6 (single node), dbt-core 1.12.5,
dbt-clickhouse 1.10.3, Prefect 3.8.8, dbt_utils 1.3.0, synthetic data:
full build 47/47 as the restricted dbt_user, idempotent reruns, late-arriving
events, empty-tenant gate, full-refresh, source freshness, grants, and the
Prefect flow (happy path, data failure without retry, infra failure with retry,
strict concurrency).

NOT tested: the `prod` target (2x2 cluster), the row-policy macro, Docker
build, Kubernetes execution, `prefect deploy`, the Cube step, and real GA4
data. The raw GA4 columns are an ASSUMPTION; see below.

## First run (dev)

1. Apply `clickhouse/01_bootstrap.sql`, then `02_grants.sql` with passwords from OpenBao.
2. Replace `raw.raw_ga4_events` DDL with the real one from your load step, and
   adapt `stg_ga4__events.sql` (columns marked ADAPT). If your connector lands
   GA4 Data API report rows instead of events, the grain differs: build
   `fact_sessions` straight from those rows and drop `fact_events`.
3. Populate `raw.tenants` (sync from the app PostgreSQL).
4. Locally: `cd predicta_dbt && dbt deps && dbt build --select tag:shared tag:ga4`
   with `CH_HOST CH_PORT CH_DBT_USER CH_DBT_PASSWORD DBT_PROFILES_DIR=.` set.
5. Run it twice; row counts and key hashes must not change (idempotency gate).
6. Kubernetes: build the image, apply `k8s/external-secret-dbt.yaml`, generate
   the work-pool template, create the pool, create the concurrency limits
   (`prefect gcl create dbt-ga4 --limit 1`, same for `dbt-shared`), then
   `prefect deploy --all`.

## Rules learned by running it

- Strategy is `delete_insert` (underscore). `unique_key` must be ONE column.
- Strings cannot be NULL in ClickHouse. Test tenant_id with
  `dbt_utils.not_empty_string` as well as `not_null`.
- Incremental models never remove rows deleted upstream. After removing or
  correcting-by-deletion in raw, run with `full_refresh=true`.
- Sessions span the lookback window. Re-aggregate whole sessions touched by new
  rows; never aggregate only the new events.
- `join_use_nulls=1` is set in the profile; facts also guard with `nullIf`.
- In the watermark subquery, never qualify the column with the outer alias.
- Profile `schema` must be a database dbt_user already owns.
- `CH_SECURE` must be `True`/`False` (capitalised).
- Prefect `concurrency()` runs unguarded if the limit does not exist unless
  `strict=True`; the default lease is 300 s. The flow handles both.

## Open decisions

- `reporting_timezone` (dbt_project.yml): UTC today. Applied only in
  `macros/to_reporting_date.sql`; `dim_tenant.timezone` is ready for tenant-local.
- Row-policy second layer: needs a design (Cube uses one ClickHouse user).
- Staging is a view with `limit 1 by` dedupe. It sorts the full table; switch
  to an incremental staging table once raw volume makes builds slow.

  ### Testing
