{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='search_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Search Console performance per day, normalised page, country, device and search type, from the combined report. Anonymised queries are left out by Search Console, so totals are lower than the page report's.
    Whole groups are re-aggregated whenever any of their rows is new, never just the new rows. -#}

with keyed as (

    select
        *,
        sipHash64(project_id, page_url) as page_key
    from {{ ref('stg_gsc__search_all_fields') }}

),

touched as (

    select distinct project_id, connection_id, date, page_url, search_type, country, device
    from keyed
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['k.project_id', 'k.connection_id', 'k.date', 'k.page_key', 'k.search_type', 'k.country', 'k.device']) }} as search_daily_key,
    toLowCardinality(any(k.customer_id))        as customer_id,
    toLowCardinality(k.project_id)         as project_id,
    toLowCardinality(any(k.source_app_id))      as source_app_id,
    toLowCardinality(k.connection_id)      as connection_id,
    toLowCardinality(any(k.source_account_id))  as source_account_id,
    k.date as date,
    toLowCardinality(k.search_type) as search_type,
    toLowCardinality(k.country) as country,
    toLowCardinality(k.device) as device,
    k.page_key as page_key,
    sum(k.clicks) as clicks,
    sum(k.impressions) as impressions,
    sum(k.sum_position) as sum_position,
    sum(k.position_impressions) as position_impressions,
    max(k._loaded_at) as _loaded_at
from keyed as k
where (k.project_id, k.connection_id, k.date, k.page_url, k.search_type, k.country, k.device) in (select project_id, connection_id, date, page_url, search_type, country, device from touched)
group by k.project_id, k.connection_id, k.date, k.page_key, k.search_type, k.country, k.device
