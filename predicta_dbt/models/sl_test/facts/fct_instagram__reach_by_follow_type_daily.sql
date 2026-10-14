{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='reach_follow_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Instagram accounts reached per day, split by whether they follow the account. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'follow_type']) }} as reach_follow_daily_key,
    toLowCardinality(customer_id)        as customer_id,
    toLowCardinality(project_id)         as project_id,
    toLowCardinality(source_app_id)      as source_app_id,
    toLowCardinality(connection_id)      as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    toLowCardinality(follow_type) as follow_type,
    reach,
    _loaded_at
from {{ ref('stg_instagram__reach_by_follow_type') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
