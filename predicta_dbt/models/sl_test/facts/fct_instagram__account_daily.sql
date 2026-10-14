{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='account_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Instagram account insights per day, one column per metric. Reach and accounts engaged count people and cannot be added across days.
    Whole groups are re-aggregated whenever any of their rows is new, never just the new rows. -#}

with keyed as (

    select
        *
    from {{ ref('stg_instagram__account_insights') }}

),

touched as (

    select distinct project_id, connection_id, date
    from keyed
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['k.project_id', 'k.connection_id', 'k.date']) }} as account_daily_key,
    toLowCardinality(any(k.customer_id))        as customer_id,
    toLowCardinality(k.project_id)         as project_id,
    toLowCardinality(any(k.source_app_id))      as source_app_id,
    toLowCardinality(k.connection_id)      as connection_id,
    toLowCardinality(any(k.source_account_id))  as source_account_id,
    k.date as date,
    sumIf(k.value, k.metric = 'reach') as reach,
    sumIf(k.value, k.metric = 'views') as views,
    sumIf(k.value, k.metric = 'likes') as likes,
    sumIf(k.value, k.metric = 'comments') as comments,
    sumIf(k.value, k.metric = 'saves') as saves,
    sumIf(k.value, k.metric = 'shares') as shares,
    sumIf(k.value, k.metric = 'reposts') as reposts,
    sumIf(k.value, k.metric = 'replies') as replies,
    sumIf(k.value, k.metric = 'profile_views') as profile_views,
    sumIf(k.value, k.metric = 'accounts_engaged') as accounts_engaged,
    sumIf(k.value, k.metric = 'website_clicks') as website_clicks,
    sumIf(k.value, k.metric = 'profile_links_taps') as profile_links_taps,
    sumIf(k.value, k.metric = 'total_interactions') as total_interactions,
    max(k._loaded_at) as _loaded_at
from keyed as k
where (k.project_id, k.connection_id, k.date) in (select project_id, connection_id, date from touched)
group by k.project_id, k.connection_id, k.date
