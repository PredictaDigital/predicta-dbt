{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='page_insights_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Facebook page insights per day, one column per metric. Metrics named *_unique count people and cannot be added across days.
    Whole groups are re-aggregated whenever any of their rows is new, never just the new rows. -#}

with keyed as (

    select
        *
    from {{ ref('stg_facebook__page_insights') }}

),

touched as (

    select distinct project_id, connection_id, date
    from keyed
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['k.project_id', 'k.connection_id', 'k.date']) }} as page_insights_daily_key,
    toLowCardinality(any(k.customer_id))        as customer_id,
    toLowCardinality(k.project_id)         as project_id,
    toLowCardinality(any(k.source_app_id))      as source_app_id,
    toLowCardinality(k.connection_id)      as connection_id,
    toLowCardinality(any(k.source_account_id))  as source_account_id,
    k.date as date,
    sumIf(k.value, k.metric = 'page_media_view') as page_media_view,
    sumIf(k.value, k.metric = 'page_views_total') as page_views_total,
    sumIf(k.value, k.metric = 'page_follows') as page_follows,
    sumIf(k.value, k.metric = 'page_video_views') as page_video_views,
    sumIf(k.value, k.metric = 'page_video_views_paid') as page_video_views_paid,
    sumIf(k.value, k.metric = 'page_video_views_organic') as page_video_views_organic,
    sumIf(k.value, k.metric = 'page_video_views_unique') as page_video_views_unique,
    sumIf(k.value, k.metric = 'page_video_view_time') as page_video_view_time,
    sumIf(k.value, k.metric = 'page_video_views_click_to_play') as page_video_views_click_to_play,
    sumIf(k.value, k.metric = 'page_total_actions') as page_total_actions,
    sumIf(k.value, k.metric = 'page_post_engagements') as page_post_engagements,
    sumIf(k.value, k.metric = 'page_daily_follows') as page_daily_follows,
    sumIf(k.value, k.metric = 'page_daily_follows_unique') as page_daily_follows_unique,
    sumIf(k.value, k.metric = 'page_daily_unfollows_unique') as page_daily_unfollows_unique,
    sumIf(k.value, k.metric = 'page_total_media_view_unique') as page_total_media_view_unique,
    sumIf(k.value, k.metric = 'page_fan_adds_by_paid_non_paid_unique') as page_fan_adds_by_paid_non_paid_unique,
    sumIf(k.value, k.metric = 'page_lifetime_engaged_followers_unique') as page_lifetime_engaged_followers_unique,
    max(k._loaded_at) as _loaded_at
from keyed as k
where (k.project_id, k.connection_id, k.date) in (select project_id, connection_id, date from touched)
group by k.project_id, k.connection_id, k.date
