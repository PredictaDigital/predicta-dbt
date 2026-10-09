## dbt rules (append to CLAUDE.md)

- One dbt run per platform, for all tenants. Never run dbt per tenant; use
  `--vars '{tenant_id: X}'` only for backfills or debugging.
- Prefect is the only trigger for dbt. No cron, no second scheduler.
- dbt reads ClickHouse `raw` only, never S3. Models write to `staging` and `marts` only.
- Facts and dims carry tenant_id first in ORDER BY; tenant-owned dims carry
  tenant_id, global reference dims (date, device, channel) do not.
- Test tenant_id with `not_null` AND `dbt_utils.not_empty_string` (ClickHouse
  Strings are never NULL).
- Incremental strategy is `delete_insert` with a single surrogate `unique_key`.
- Incremental models cannot remove rows deleted upstream: use full-refresh.
- The reporting timezone lives in `var('reporting_timezone')` and is applied
  only through the `to_reporting_date()` macro. Never hard-code a timezone.
- Never read `target/` from a previous run; delete run_results.json first.
- dbt is not the semantic layer: Cube reads `marts` only; metrics stay in Cube.
- Pin dbt-core, dbt-clickhouse and Prefect; re-check incremental behaviour on upgrade.
