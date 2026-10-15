{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='search_daily_key',
    engine='MergeTree()',
    order_by='(project_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Domain mart for SEO search. Grain: project, connection, date, page, search type, country, device.
    Today the only source at this grain is the Search Console combined report, so the mart is that
    fact carried through with its lineage columns. A second search source would be added with
    UNION ALL at the same grain, never joined at query time. -#}

select
    search_daily_key,
    customer_id,
    project_id,
    source_app_id,
    connection_id,
    source_account_id,
    date,
    page_key,
    search_type,
    country,
    device,
    clicks,
    impressions,
    sum_position,
    position_impressions,
    _loaded_at
from {{ ref('fct_gsc__search_daily') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
