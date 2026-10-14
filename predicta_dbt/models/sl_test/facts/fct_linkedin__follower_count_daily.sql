{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='follower_count_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- LinkedIn page follower total per snapshot day. Total at that day: take the latest, do not sum. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date']) }} as follower_count_daily_key,
    toLowCardinality(customer_id)        as customer_id,
    toLowCardinality(project_id)         as project_id,
    toLowCardinality(source_app_id)      as source_app_id,
    toLowCardinality(connection_id)      as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    first_degree_size,
    _loaded_at
from {{ ref('stg_linkedin__follower_count') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
