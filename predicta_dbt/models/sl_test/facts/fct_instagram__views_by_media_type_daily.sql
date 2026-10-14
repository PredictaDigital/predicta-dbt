{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='views_media_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Instagram views per day, split by where the media appears. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'media_product_type']) }} as views_media_daily_key,
    toLowCardinality(customer_id)        as customer_id,
    toLowCardinality(project_id)         as project_id,
    toLowCardinality(source_app_id)      as source_app_id,
    toLowCardinality(connection_id)      as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    toLowCardinality(media_product_type) as media_product_type,
    views,
    _loaded_at
from {{ ref('stg_instagram__views_by_media_type') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
