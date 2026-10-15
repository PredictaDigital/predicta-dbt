{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='channel_daily_key',
    engine='MergeTree()',
    order_by='(project_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Digital marketing mart. Grain: project, date, channel group.
    One row per channel group and day with the sources side by side in source-qualified columns:
    ga4_sessions, gsc_clicks, ppc_spend_usd, platform_conversions and so on. Built by UNION ALL
    of the source facts at this shared grain; each branch fills only its own columns and the rest
    stay zero. No column adds measures from different sources and no ratio crosses domains.
    GA4 maps to a channel group through dim_channel, Search Console to Organic Search, and
    Google Ads to Paid Search. -#}

with src as (

    select
        f.customer_id as customer_id, f.project_id as project_id, f.date as date,
        ifNull(c.channel_group, 'Unassigned') as channel_group,
        toInt64(f.sessions) as ga4_sessions, toInt64(f.engaged_sessions) as ga4_engaged_sessions,
        toInt64(0) as gsc_clicks, toInt64(0) as gsc_impressions,
        toInt64(0) as ppc_impressions, toInt64(0) as ppc_clicks, toFloat64(0) as ppc_spend_usd, toFloat64(0) as platform_conversions,
        f._loaded_at as _loaded_at
    from {{ ref('fct_ga4__traffic_daily') }} as f
    left join {{ ref('sl_dim_channel') }} as c on f.source = c.source and f.medium = c.medium

    union all

    select
        customer_id, project_id, date, 'Organic Search',
        toInt64(0), toInt64(0),
        toInt64(clicks), toInt64(impressions),
        toInt64(0), toInt64(0), toFloat64(0), toFloat64(0),
        _loaded_at
    from {{ ref('fct_gsc__site_daily') }}

    union all

    select
        customer_id, project_id, date, 'Paid Search',
        toInt64(0), toInt64(0), toInt64(0), toInt64(0),
        toInt64(impressions), toInt64(clicks), toFloat64(spend_usd), toFloat64(platform_conversions),
        _loaded_at
    from {{ ref('mart_ppc__campaign_daily') }}

),

touched as (

    select distinct project_id, date, channel_group
    from src
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['s.project_id', 's.date', 's.channel_group']) }} as channel_daily_key,
    toLowCardinality(any(s.customer_id))   as customer_id,
    toLowCardinality(s.project_id)         as project_id,
    s.date                                 as date,
    toLowCardinality(s.channel_group)      as channel_group,
    sum(s.ga4_sessions)                    as ga4_sessions,
    sum(s.ga4_engaged_sessions)            as ga4_engaged_sessions,
    sum(s.gsc_clicks)                      as gsc_clicks,
    sum(s.gsc_impressions)                 as gsc_impressions,
    sum(s.ppc_impressions)                 as ppc_impressions,
    sum(s.ppc_clicks)                      as ppc_clicks,
    sum(s.ppc_spend_usd)                   as ppc_spend_usd,
    sum(s.platform_conversions)            as platform_conversions,
    max(s._loaded_at)                      as _loaded_at
from src as s
where (s.project_id, s.date, s.channel_group) in (select project_id, date, channel_group from touched)
group by s.project_id, s.date, s.channel_group
