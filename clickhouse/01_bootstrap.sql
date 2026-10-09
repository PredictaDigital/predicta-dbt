-- Databases. dbt writes to staging and marts; Prefect loads raw.
CREATE DATABASE IF NOT EXISTS raw;
CREATE DATABASE IF NOT EXISTS staging;
CREATE DATABASE IF NOT EXISTS marts;

-- Tenant metadata, synced from the app PostgreSQL by a small Prefect task
-- (or replace with ClickHouse's PostgreSQL engine). Reference data only.
CREATE TABLE IF NOT EXISTS raw.tenants
(
    tenant_id   String,
    tenant_name String,
    timezone    String DEFAULT 'UTC',
    plan        String DEFAULT 'standard',
    created_at  DateTime DEFAULT now()
)
ENGINE = MergeTree ORDER BY tenant_id;

-- ASSUMED raw GA4 event shape. Replace with the real DDL produced by your
-- land-raw-to-clickhouse skill; then adjust stg_ga4__events to match.
CREATE TABLE IF NOT EXISTS raw.raw_ga4_events
(
    tenant_id            String,
    event_timestamp      DateTime64(6, 'UTC'),
    event_name           String,
    user_pseudo_id       String,
    ga_session_id        Int64,
    page_location        String,
    device_category      String,
    traffic_source       String,
    traffic_medium       String,
    traffic_campaign     String,
    engagement_time_msec Nullable(UInt32),
    _loaded_at           DateTime64(3, 'UTC') DEFAULT now64(3),
    _source_file         String DEFAULT ''
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_timestamp)
ORDER BY (tenant_id, event_timestamp);
