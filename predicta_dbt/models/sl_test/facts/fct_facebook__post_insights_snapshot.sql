{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='post_insights_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Facebook post insights as lifetime totals at each snapshot day, one column per metric. Each snapshot restates the running total: use the latest snapshot per post, do not sum across days.
    Whole groups are re-aggregated whenever any of their rows is new, never just the new rows. -#}

with keyed as (

    select
        *,
        sipHash64(project_id, post_id) as post_key
    from {{ ref('stg_facebook__post_insights') }}

),

touched as (

    select distinct project_id, connection_id, date, post_id
    from keyed
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['k.project_id', 'k.connection_id', 'k.date', 'k.post_key']) }} as post_insights_key,
    toLowCardinality(any(k.customer_id))        as customer_id,
    toLowCardinality(k.project_id)         as project_id,
    toLowCardinality(any(k.source_app_id))      as source_app_id,
    toLowCardinality(k.connection_id)      as connection_id,
    toLowCardinality(any(k.source_account_id))  as source_account_id,
    k.date as date,
    k.post_key as post_key,
    sumIf(k.value, k.metric = 'post_media_view') as post_media_view,
    sumIf(k.value, k.metric = 'post_total_media_view_unique') as post_total_media_view_unique,
    sumIf(k.value, k.metric = 'post_clicks') as post_clicks,
    sumIf(k.value, k.metric = 'post_video_views') as post_video_views,
    sumIf(k.value, k.metric = 'post_video_views_unique') as post_video_views_unique,
    sumIf(k.value, k.metric = 'post_video_complete_views_30s') as post_video_complete_views_30s,
    sumIf(k.value, k.metric = 'post_clicks_by_type') as post_clicks_by_type,
    sumIf(k.value, k.metric = 'post_activity_by_action_type') as post_activity_by_action_type,
    sumIf(k.value, k.metric = 'post_reactions_by_type_total') as post_reactions_by_type_total,
    max(k._loaded_at) as _loaded_at
from keyed as k
where (k.project_id, k.connection_id, k.date, k.post_id) in (select project_id, connection_id, date, post_id from touched)
group by k.project_id, k.connection_id, k.date, k.post_key
