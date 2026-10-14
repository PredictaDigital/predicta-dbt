{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='audit_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Grain: project, connection, date, page_key, device strategy, audit id.
    One row per Lighthouse check result. audit_failed is 1 when the audit scored
    below 1 (a score of -1 means not scored and counts as neither). Audit text
    lives in dim_audit. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'page_url', 'strategy', 'audit_id']) }} as audit_daily_key,
    toLowCardinality(customer_id)       as customer_id,
    toLowCardinality(project_id)        as project_id,
    toLowCardinality(source_app_id)     as source_app_id,
    toLowCardinality(connection_id)     as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    sipHash64(project_id, page_url)     as page_key,
    toLowCardinality(strategy)          as strategy,
    toLowCardinality(audit_id)          as audit_id,
    score,
    toInt64(score >= 0 AND score < 1)   as audit_failed,
    toInt64(score >= 0)                 as audit_scored,
    _loaded_at
from {{ ref('stg_lighthouse__audit') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
