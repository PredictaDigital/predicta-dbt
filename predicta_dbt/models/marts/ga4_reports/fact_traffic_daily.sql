{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='traffic_daily_key',
    engine='MergeTree()',
    order_by='(tenant_id, date_day, traffic_daily_key)',
    partition_by='toYYYYMM(date_day)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per tenant, date, source and medium. Combines the traffic
    sources report (users, sessions, page views, bounce) with the acquisition
    report (engaged sessions, events, revenue). Source/medium are kept as
    degenerate columns; channel_key links to dim_channel. -#}

with combined as (

    select
        tenant_id, date_day, source, medium,
        total_users, new_users, sessions as traffic_sessions, pageviews,
        bounce_rate * sessions as bounce_weighted,
        toInt64(0) as acquisition_sessions, toInt64(0) as engaged_sessions,
        toInt64(0) as event_count, toFloat64(0) as total_revenue,
        toFloat64(0) as user_engagement_duration_sec,
        _loaded_at
    from {{ ref('stg_ga4_lc__traffic_sources') }}

    union all

    select
        tenant_id, date_day, source, medium,
        toInt64(0), toInt64(0), toInt64(0), toInt64(0),
        toFloat64(0),
        sessions, engaged_sessions, event_count, total_revenue, user_engagement_duration_sec,
        _loaded_at
    from {{ ref('stg_ga4_lc__traffic_acquisition_source_medium') }}

),

aggregated as (

    select
        tenant_id, date_day, source, medium,
        sum(total_users)                     as total_users,
        sum(new_users)                       as new_users,
        sum(traffic_sessions)                as traffic_sessions,
        sum(acquisition_sessions)            as acquisition_sessions,
        sum(pageviews)                       as pageviews,
        sum(bounce_weighted)                 as bounce_weighted,
        sum(engaged_sessions)                as engaged_sessions,
        sum(event_count)                     as event_count,
        sum(total_revenue)                   as total_revenue,
        sum(user_engagement_duration_sec)    as user_engagement_duration_sec,
        max(_loaded_at)                      as _loaded_at
    from combined
    group by tenant_id, date_day, source, medium

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['a.tenant_id', 'a.date_day', 'a.source', 'a.medium']) }} as traffic_daily_key,
        a.tenant_id                          as tenant_id,
        a.date_day                           as date_day,
        {{ dbt_utils.generate_surrogate_key(
            ["coalesce(nullIf(m.channel_group, ''), 'Unassigned')"]) }} as channel_key,
        a.source                             as source,
        a.medium                             as medium,
        a.total_users                        as total_users,
        a.new_users                          as new_users,
        if(a.traffic_sessions > 0, a.traffic_sessions, a.acquisition_sessions) as sessions,
        a.pageviews                          as pageviews,
        a.engaged_sessions                   as engaged_sessions,
        a.event_count                        as event_count,
        a.total_revenue                      as total_revenue,
        a.user_engagement_duration_sec       as user_engagement_duration_sec,
        a.bounce_weighted / nullIf(a.traffic_sessions, 0) as bounce_rate,
        a._loaded_at                         as _loaded_at
    from aggregated as a
    left join {{ ref('channel_mapping') }} as m
        on a.source = m.source and a.medium = m.medium

)

select * from final
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
