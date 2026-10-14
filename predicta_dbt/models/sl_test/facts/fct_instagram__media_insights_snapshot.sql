{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='media_insights_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Instagram media insights as lifetime totals at each snapshot day, one column per metric. Use the latest snapshot per media item; do not sum across days.
    Whole groups are re-aggregated whenever any of their rows is new, never just the new rows. -#}

with keyed as (

    select
        *,
        sipHash64(project_id, media_id) as media_key
    from {{ ref('stg_instagram__media_insights') }}

),

touched as (

    select distinct project_id, connection_id, date, media_id
    from keyed
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['k.project_id', 'k.connection_id', 'k.date', 'k.media_key']) }} as media_insights_key,
    toLowCardinality(any(k.customer_id))        as customer_id,
    toLowCardinality(k.project_id)         as project_id,
    toLowCardinality(any(k.source_app_id))      as source_app_id,
    toLowCardinality(k.connection_id)      as connection_id,
    toLowCardinality(any(k.source_account_id))  as source_account_id,
    k.date as date,
    k.media_key as media_key,
    sumIf(k.value, k.metric = 'reach') as reach,
    sumIf(k.value, k.metric = 'views') as views,
    sumIf(k.value, k.metric = 'likes') as likes,
    sumIf(k.value, k.metric = 'comments') as comments,
    sumIf(k.value, k.metric = 'shares') as shares,
    sumIf(k.value, k.metric = 'saved') as saved,
    sumIf(k.value, k.metric = 'follows') as follows,
    sumIf(k.value, k.metric = 'reposts') as reposts,
    sumIf(k.value, k.metric = 'profile_activity') as profile_activity,
    sumIf(k.value, k.metric = 'profile_visits') as profile_visits,
    sumIf(k.value, k.metric = 'total_interactions') as total_interactions,
    max(k._loaded_at) as _loaded_at
from keyed as k
where (k.project_id, k.connection_id, k.date, k.media_id) in (select project_id, connection_id, date, media_id from touched)
group by k.project_id, k.connection_id, k.date, k.media_key
