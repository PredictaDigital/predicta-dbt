{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='page_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Grain: project, connection, date, page_key (normalised URL).
    Several GA4 paths (tracking parameters, mixed case) collapse onto one page_key,
    so a group can be touched by only some of its rows. We therefore find the
    groups touched by new rows and re-aggregate ALL their staging rows, never just
    the new ones. -#}

with keyed as (

    select
        *,
        sipHash64(project_id, page_url) as page_key
    from {{ ref('stg_ga4__pages') }}

),

touched as (

    select distinct project_id, connection_id, date, page_key
    from keyed
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['k.project_id', 'k.connection_id', 'k.date', 'k.page_key']) }} as page_daily_key,
    toLowCardinality(any(k.customer_id))        as customer_id,
    toLowCardinality(k.project_id)              as project_id,
    toLowCardinality(any(k.source_app_id))      as source_app_id,
    toLowCardinality(k.connection_id)           as connection_id,
    toLowCardinality(any(k.source_account_id))  as source_account_id,
    k.date                                      as date,
    k.page_key                                  as page_key,
    sum(k.pageviews)                            as pageviews,
    max(k._loaded_at)                           as _loaded_at
from keyed as k
where (k.project_id, k.connection_id, k.date, k.page_key) in (select project_id, connection_id, date, page_key from touched)
group by k.project_id, k.connection_id, k.date, k.page_key
