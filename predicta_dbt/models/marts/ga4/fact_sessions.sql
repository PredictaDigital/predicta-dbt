{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='session_key',
    engine='MergeTree()',
    order_by='(tenant_id, session_date, session_key)',
    partition_by='toYYYYMM(session_date)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per GA4 session.
    A session can span the lookback boundary, so an incremental run must not
    aggregate only the new events (that would overwrite a session with a
    partial total). Instead: find the sessions touched by new rows, then
    re-aggregate ALL events for those sessions. -#}

with touched_sessions as (

    {% if is_incremental() %}
    select distinct session_key
    from {{ ref('stg_ga4__events') }}
    where {{ incremental_watermark() }}
    {% else %}
    select distinct session_key from {{ ref('stg_ga4__events') }}
    {% endif %}

),

events as (

    select *
    from {{ ref('stg_ga4__events') }}
    where session_key in (select session_key from touched_sessions)

),

sessions as (

    select
        session_key,
        any(tenant_id)                                       as tenant_id,
        min(event_ts)                                        as session_start,
        max(event_ts)                                        as session_end,
        count()                                              as events,
        countIf(event_name = 'page_view')                    as pageviews,
        countIf(event_name = 'purchase')                     as purchases,
        sum(engagement_time_msec)                            as engagement_time_msec,
        -- first-touch attributes of the session
        argMin(page_location, event_ts)                      as landing_page_location,
        argMin(device_category, event_ts)                    as device_category,
        argMin(source, event_ts)                             as source,
        argMin(medium, event_ts)                             as medium,
        argMin(campaign, event_ts)                           as campaign,
        max(_loaded_at)                                      as _loaded_at
    from events
    group by session_key

)

select
    s.tenant_id                                              as tenant_id,
    s.session_key                                            as session_key,
    {{ to_reporting_date('s.session_start') }}               as session_date,
    s.session_start                                          as session_start,
    s.session_end                                            as session_end,

    {{ dbt_utils.generate_surrogate_key(
        ['s.tenant_id', 'path(s.landing_page_location)']) }} as landing_page_key,
    {{ dbt_utils.generate_surrogate_key(
        ["coalesce(nullIf(s.device_category, ''), 'unknown')"]) }} as device_key,
    {{ dbt_utils.generate_surrogate_key(
        ["coalesce(nullIf(m.channel_group, ''), 'Unassigned')"]) }}      as channel_key,

    s.source                                                 as source,
    s.medium                                                 as medium,
    s.campaign                                               as campaign,

    -- measures
    toUInt8(1)                                               as session_count,
    s.events                                                 as events,
    s.pageviews                                              as pageviews,
    s.purchases                                              as purchases,
    s.engagement_time_msec                                   as engagement_time_msec,
    -- GA4 definition: >10 s engaged, or a conversion, or 2+ page views
    toUInt8(s.engagement_time_msec > 10000
            or s.purchases > 0
            or s.pageviews >= 2)                             as is_engaged_session,

    s._loaded_at                                             as _loaded_at

from sessions as s
left join {{ ref('channel_mapping') }} as m
    on s.source = m.source and s.medium = m.medium
