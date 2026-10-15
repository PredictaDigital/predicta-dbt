{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='page_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Facebook page audience snapshot per day. Counts are totals at that day, not daily changes: average or take the latest, do not sum across days. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date']) }} as page_daily_key,
    toLowCardinality(customer_id)        as customer_id,
    toLowCardinality(project_id)         as project_id,
    toLowCardinality(source_app_id)      as source_app_id,
    toLowCardinality(connection_id)      as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    fan_count,
    followers_count,
    _loaded_at
from {{ ref('stg_facebook__page') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
