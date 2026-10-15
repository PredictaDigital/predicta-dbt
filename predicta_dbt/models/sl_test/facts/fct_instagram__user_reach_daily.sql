{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='user_reach_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Instagram reach per day, plus trailing 28-day and weekly reach reported on that day (those two are not additive). -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date']) }} as user_reach_daily_key,
    toLowCardinality(customer_id)        as customer_id,
    toLowCardinality(project_id)         as project_id,
    toLowCardinality(source_app_id)      as source_app_id,
    toLowCardinality(connection_id)      as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    reach,
    reach_days_28,
    reach_week,
    _loaded_at
from {{ ref('stg_instagram__user_reach') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
