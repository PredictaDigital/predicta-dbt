{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='traffic_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Grain: project, connection, date, session source, session medium.
    One row per key (staging already holds the latest extract). Additive measures
    only; ratios are computed in the semantic layer. Re-sent rows carry a newer
    _loaded_at and are picked up by the watermark; delete_insert replaces them. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'source', 'medium']) }} as traffic_daily_key,
    toLowCardinality(customer_id)       as customer_id,
    toLowCardinality(project_id)        as project_id,
    toLowCardinality(source_app_id)     as source_app_id,
    toLowCardinality(connection_id)     as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    toLowCardinality(source)            as source,
    toLowCardinality(medium)            as medium,
    sessions,
    engaged_sessions,
    total_users,
    new_users,
    pageviews,
    session_duration_sec,
    _loaded_at
from {{ ref('stg_ga4__traffic_sources') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
