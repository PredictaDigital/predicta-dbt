{#- Grain: one row per GA4 event, deduplicated.
    Responsibilities: type, rename, unnest, dedupe, keep tenant_id and _loaded_at.
    NOT here: joins to dimensions, business logic, aggregation. -#}

with source as (

    select * from {{ source('raw', 'raw_ga4_events') }}

),

typed as (

    select
        tenant_id,

        -- ADAPT: event_timestamp assumed DateTime64(6, 'UTC') already. If the
        -- connector lands GA4's raw microsecond integer, use
        -- fromUnixTimestamp64Micro(event_timestamp) instead.
        toDateTime64(event_timestamp, 3, 'UTC')       as event_ts,
        event_name,
        user_pseudo_id,
        ga_session_id,

        page_location,
        device_category,
        lower(coalesce(nullIf(traffic_source, ''), '(direct)'))  as source,
        lower(coalesce(nullIf(traffic_medium, ''), '(none)'))    as medium,
        nullIf(traffic_campaign, '')                  as campaign,

        toUInt32(ifNull(engagement_time_msec, 0))     as engagement_time_msec,

        _loaded_at

    from source

),

keyed as (

    select
        *,
        {{ dbt_utils.generate_surrogate_key(
            ['tenant_id', 'user_pseudo_id', 'ga_session_id']) }}        as session_key,
        {{ dbt_utils.generate_surrogate_key(
            ['tenant_id', 'user_pseudo_id', 'ga_session_id',
             'event_name', 'event_ts']) }}                              as event_key
    from typed

)

-- Dedupe: keep the latest load of each event. Re-landed files and GA4
-- reprocessing both produce duplicates, so this is what makes reruns safe.
select *
from keyed
order by _loaded_at desc
limit 1 by event_key
