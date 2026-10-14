{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='site_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Grain: project, connection, date, search type (whole site, no page or query).
    sum_position and position_impressions are additive; average position is
    sum_position / position_impressions, computed in the semantic layer. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'search_type']) }} as site_daily_key,
    toLowCardinality(customer_id)       as customer_id,
    toLowCardinality(project_id)        as project_id,
    toLowCardinality(source_app_id)     as source_app_id,
    toLowCardinality(connection_id)     as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    toLowCardinality(search_type)       as search_type,
    clicks,
    impressions,
    sum_position,
    position_impressions,
    _loaded_at
from {{ ref('stg_gsc__search_by_date') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
