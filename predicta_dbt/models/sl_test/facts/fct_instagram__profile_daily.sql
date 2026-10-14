{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='profile_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Instagram profile snapshot per day. Counts are totals at that day: average or take the latest, do not sum. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date']) }} as profile_daily_key,
    toLowCardinality(customer_id)        as customer_id,
    toLowCardinality(project_id)         as project_id,
    toLowCardinality(source_app_id)      as source_app_id,
    toLowCardinality(connection_id)      as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    followers_count,
    follows_count,
    media_count,
    _loaded_at
from {{ ref('stg_instagram__profile') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
