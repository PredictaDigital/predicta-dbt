{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='social_daily_key',
    engine='MergeTree()',
    order_by='(project_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Domain mart for social media. Grain: project, date, platform (facebook, instagram, linkedin).
    Built by UNION ALL of the platform facts at this shared grain. Each platform fills only its own
    source-qualified columns (fb_, ig_, li_) and the rest stay zero. The platforms count different things
    (page views, views, impressions), so no column adds measures from different platforms and no ratio crosses
    platforms. Only flow measures that can be summed over days are included; follower and reach totals
    stay in the detail facts. Whole groups are re-aggregated whenever any of their rows is new. -#}

with src as (

    select
        customer_id, project_id, date, 'facebook' as platform,
        toFloat64(page_views_total) as fb_page_views, toFloat64(page_media_view) as fb_media_views,
        toFloat64(page_post_engagements) as fb_post_engagements, toFloat64(page_daily_follows) as fb_new_follows,
        toFloat64(0) as ig_views, toFloat64(0) as ig_likes, toFloat64(0) as ig_comments, toFloat64(0) as ig_shares,
        toFloat64(0) as ig_saves, toFloat64(0) as ig_total_interactions, toFloat64(0) as ig_profile_views, toFloat64(0) as ig_website_clicks,
        toFloat64(0) as li_impressions, toFloat64(0) as li_clicks, toFloat64(0) as li_likes, toFloat64(0) as li_comments,
        toFloat64(0) as li_shares, toFloat64(0) as li_organic_follower_gain, toFloat64(0) as li_paid_follower_gain,
        _loaded_at
    from {{ ref('fct_facebook__page_insights_daily') }}

    union all

    select
        customer_id, project_id, date, 'instagram',
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        toFloat64(views), toFloat64(likes), toFloat64(comments), toFloat64(shares),
        toFloat64(saves), toFloat64(total_interactions), toFloat64(profile_views), toFloat64(website_clicks),
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        _loaded_at
    from {{ ref('fct_instagram__account_daily') }}

    union all

    select
        customer_id, project_id, date, 'linkedin',
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        toFloat64(impressions), toFloat64(clicks), toFloat64(likes), toFloat64(comments),
        toFloat64(shares), toFloat64(0), toFloat64(0),
        _loaded_at
    from {{ ref('fct_linkedin__share_daily') }}

    union all

    select
        customer_id, project_id, date, 'linkedin',
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        toFloat64(0), toFloat64(0), toFloat64(0), toFloat64(0),
        toFloat64(0), toFloat64(organic_follower_gain), toFloat64(paid_follower_gain),
        _loaded_at
    from {{ ref('fct_linkedin__follower_gains_daily') }}

),

touched as (

    select distinct project_id, date, platform
    from src
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['s.project_id', 's.date', 's.platform']) }} as social_daily_key,
    toLowCardinality(any(s.customer_id))   as customer_id,
    toLowCardinality(s.project_id)         as project_id,
    s.date                                 as date,
    toLowCardinality(s.platform)           as platform,
    sum(s.fb_page_views)                   as fb_page_views,
    sum(s.fb_media_views)                  as fb_media_views,
    sum(s.fb_post_engagements)             as fb_post_engagements,
    sum(s.fb_new_follows)                  as fb_new_follows,
    sum(s.ig_views)                        as ig_views,
    sum(s.ig_likes)                        as ig_likes,
    sum(s.ig_comments)                     as ig_comments,
    sum(s.ig_shares)                       as ig_shares,
    sum(s.ig_saves)                        as ig_saves,
    sum(s.ig_total_interactions)           as ig_total_interactions,
    sum(s.ig_profile_views)                as ig_profile_views,
    sum(s.ig_website_clicks)               as ig_website_clicks,
    sum(s.li_impressions)                  as li_impressions,
    sum(s.li_clicks)                       as li_clicks,
    sum(s.li_likes)                        as li_likes,
    sum(s.li_comments)                     as li_comments,
    sum(s.li_shares)                       as li_shares,
    sum(s.li_organic_follower_gain)        as li_organic_follower_gain,
    sum(s.li_paid_follower_gain)           as li_paid_follower_gain,
    max(s._loaded_at)                      as _loaded_at
from src as s
where (s.project_id, s.date, s.platform) in (select project_id, date, platform from touched)
group by s.project_id, s.date, s.platform
