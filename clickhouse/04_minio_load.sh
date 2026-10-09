#!/bin/bash
# Incremental load of Airbyte CSV files from MinIO into raw.ga4_lc_* tables.
#   docker compose exec clickhouse bash /sql/04_minio_load.sh
# Safe to re-run: only files not yet in the raw table (by _source_file) are read.
# Airbyte writes one CSV per sync; the payload sits in the _airbyte_data JSON
# column, which dbt unpacks in staging. Raw keeps it untouched.
set -euo pipefail
c() { clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --multiquery "$@"; }

: "${MINIO_ENDPOINT:?}" "${MINIO_BUCKET:?}" "${MINIO_ACCESS_KEY:?}" "${MINIO_SECRET_KEY:?}"
PREFIX="${MINIO_PREFIX:-airbyte_raw}"

# Airbyte stream names to load (folder = GA4_LC_<name>).
TABLES=(website_overview daily_active_users traffic_sources
        traffic_acquisition_session_source_medium_report
        pages devices locations ecommerce_purchases_item_name_report)

for t in "${TABLES[@]}"; do
  tbl="raw.ga4_lc_${t}"
  url="${MINIO_ENDPOINT}/${MINIO_BUCKET}/${PREFIX}/GA4_LC_${t}/*.csv"
  c -q "
    CREATE TABLE IF NOT EXISTS ${tbl}
    (
        _airbyte_raw_id        String,
        _airbyte_extracted_at  Int64,
        _airbyte_data          String,
        _source_file           String,
        _loaded_at             DateTime64(3, 'UTC') DEFAULT now64(3)
    )
    ENGINE = MergeTree
    ORDER BY (_source_file, _airbyte_extracted_at)"
  before=$(c -q "SELECT count() FROM ${tbl}")
  c -q "
    INSERT INTO ${tbl} (_airbyte_raw_id, _airbyte_extracted_at, _airbyte_data, _source_file)
    SELECT ifNull(_airbyte_raw_id, ''), ifNull(_airbyte_extracted_at, 0), ifNull(_airbyte_data, '{}'), _path
    FROM s3('${url}', '${MINIO_ACCESS_KEY}', '${MINIO_SECRET_KEY}', 'CSVWithNames',
            '_airbyte_raw_id Nullable(String), _airbyte_extracted_at Nullable(Int64), _airbyte_meta Nullable(String), _airbyte_generation_id Nullable(Int64), _airbyte_data Nullable(String)')
    WHERE _path NOT IN (SELECT DISTINCT _source_file FROM ${tbl})"
  after=$(c -q "SELECT count() FROM ${tbl}")
  echo "${tbl}: +$((after - before)) rows (total ${after})"
done

# Tenant metadata for the Little Cheeks GA4 property (see seeds/ga4_property_tenant.csv)
c -q "INSERT INTO raw.tenants (tenant_id, tenant_name, timezone, plan)
      SELECT 't_littlecheeks', 'Little Cheeks', 'UTC', 'standard'
      WHERE NOT EXISTS (SELECT 1 FROM raw.tenants WHERE tenant_id = 't_littlecheeks')"
echo "minio load complete"
