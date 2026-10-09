#!/bin/bash
# Runs once, on first start of an empty data volume (ClickHouse image convention).
set -euo pipefail
c() { clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --multiquery; }

c < /sql/01_bootstrap.sql
sed -e "s/__DBT_PASSWORD__/${DBT_PASSWORD}/" \
    -e "s/__CUBE_PASSWORD__/${CUBE_PASSWORD}/" /sql/02_grants.sql | c
if [ "${LOAD_SAMPLE_DATA:-true}" = "true" ]; then
  c < /sql/03_sample_data.sql
fi
echo "predicta init complete"
