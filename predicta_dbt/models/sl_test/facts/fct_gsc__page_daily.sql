{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='page_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Grain: project, connection, date, page_key (normalised URL), search type.
    URL variants collapse onto one page_key, so we re-aggregate every staging row
    of any group touched by new rows (see fct_ga4__page_daily). -#}

with keyed as (

    select
        *,
        sipHash64(project_id, page_url) as page_key
    from {{ ref('stg_gsc__search_by_page') }}

),

touched as (

    select distinct project_id, connection_id, date, page_key, search_type
    from keyed
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['k.project_id', 'k.connection_id', 'k.date', 'k.page_key', 'k.search_type']) }} as page_daily_key,
    toLowCardinality(any(k.customer_id))        as customer_id,
    toLowCardinality(k.project_id)              as project_id,
    toLowCardinality(any(k.source_app_id))      as source_app_id,
    toLowCardinality(k.connection_id)           as connection_id,
    toLowCardinality(any(k.source_account_id))  as source_account_id,
    k.date                                      as date,
    k.page_key                                  as page_key,
    toLowCardinality(k.search_type)             as search_type,
    sum(k.clicks)                               as clicks,
    sum(k.impressions)                          as impressions,
    sum(k.sum_position)                         as sum_position,
    sum(k.position_impressions)                 as position_impressions,
    max(k._loaded_at)                           as _loaded_at
from keyed as k
where (k.project_id, k.connection_id, k.date, k.page_key, k.search_type) in (select project_id, connection_id, date, page_key, search_type from touched)
group by k.project_id, k.connection_id, k.date, k.page_key, k.search_type
