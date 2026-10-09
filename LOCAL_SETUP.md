# Local setup on Windows (low-RAM, 8 GB)

Run these in PowerShell from the folder where you unzipped the package.
Close your browser and heavy apps first. Docker Desktop must be running.

## 0. Cap WSL memory (once)
Create `C:\Users\<you>\.wslconfig`:

    [wsl2]
    memory=3GB
    processors=2

Then: `wsl --shutdown` and restart Docker Desktop.

## 1. Configure passwords (local only)
    copy .env.example .env

## 2. Start ClickHouse (first start runs the init script)
    docker compose up -d clickhouse
    docker compose ps            # wait until STATUS shows (healthy)
    docker compose logs clickhouse | Select-String "predicta init complete"

## 3. Check the data and permissions
    docker compose exec clickhouse clickhouse-client --user admin --password LocalAdminPass1 -q "select count() from raw.raw_ga4_events"
    # expect 1890 (900 distinct events + 90 duplicates per the sample data)

## 4. Build the dbt image (first build downloads packages from GitHub)
    docker compose build dbt

## 5. Run dbt
    docker compose run --rm dbt debug
    docker compose run --rm dbt build --select tag:shared tag:ga4
    # expect: PASS=52 ... ERROR=0. Run it a second time: same result.

## 6. Look at the results
    docker compose exec clickhouse clickhouse-client --user admin --password LocalAdminPass1 -q "select count() from marts.fact_events"
    # expect 1800 (duplicates removed)

## Stop / reset
    docker compose down          # stop, keep data
    docker compose down -v       # stop AND delete data (re-runs the init script next time)

## If it fails
- `(unhealthy)` or restarting: `docker compose logs clickhouse`. Out-of-memory
  means raise `mem_limit` in docker-compose.yml, if you have the RAM.
- `docker compose build dbt` errors: send me the last 20 lines. This is the first
  time the Dockerfile has been built, so a fix may be needed.
- Port 8123 already in use: change `"8123:8123"` to `"8124:8123"` in the compose file.
- Init script changed? It only runs on an empty volume: use `down -v` first.

Not included yet: Prefect. Add it only after steps 1-6 pass.

## MinIO -> ClickHouse -> dbt (GA4_LC_* Airbyte reports)
Credentials go in `.env` (see `.env.example`). `MINIO_ENDPOINT` must be the S3 API
URL (https://s3.infra.predictaanalytics.io), not the web console URL.

    # 1. Load new CSV files from MinIO into raw.ga4_lc_* (incremental, re-runnable)
    docker compose up -d clickhouse        # recreates the container once to pick up MINIO_* env
    docker compose exec clickhouse bash /sql/04_minio_load.sh

    # 2. Transform
    docker compose run --rm dbt build --select tag:shared tag:ga4 tag:ga4_reports

Add a table: add its stream name to `TABLES` in `clickhouse/04_minio_load.sh`, a source
entry, a `stg_ga4_lc__*` model and a fact/dim. Add a client: add its property_id to
`seeds/ga4_property_tenant.csv` and a tenant row in the load script.
