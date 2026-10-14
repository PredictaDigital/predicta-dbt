{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='device_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Grain: project, connection, date, search type, device (desktop, mobile, tablet). -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'search_type', 'device']) }} as device_daily_key,
    toLowCardinality(customer_id)       as customer_id,
    toLowCardinality(project_id)        as project_id,
    toLowCardinality(source_app_id)     as source_app_id,
    toLowCardinality(connection_id)     as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    toLowCardinality(search_type)       as search_type,
    toLowCardinality(device)            as device,
    clicks,
    impressions,
    sum_position,
    position_impressions,
    _loaded_at
from {{ ref('stg_gsc__search_by_device') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
