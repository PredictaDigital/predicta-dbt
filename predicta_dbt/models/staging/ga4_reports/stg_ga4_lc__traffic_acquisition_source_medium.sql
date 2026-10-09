{#- Grain: one row per property, date, source and medium.
    Airbyte re-pulls a rolling date window each sync, so the same natural key
    arrives in several files. Keep the latest sync (highest _airbyte_extracted_at).
    Responsibilities: unpack JSON, type, rename, map tenant, dedupe. -#}

with source as (

    select * from {{ source('raw_ga4_lc', 'ga4_lc_traffic_acquisition_session_source_medium_report') }}

),

typed as (

    select
        ifNull(m.tenant_id, 'unmapped')                                     as tenant_id,
        JSONExtractString(s._airbyte_data, 'property_id')                   as property_id,
        toDate(parseDateTimeBestEffort(JSONExtractString(s._airbyte_data, 'date'))) as date_day,
        lower(coalesce(nullIf(JSONExtractString(s._airbyte_data, 'sessionSource'), ''), '(direct)')) as source,
        lower(coalesce(nullIf(JSONExtractString(s._airbyte_data, 'sessionMedium'), ''), '(none)')) as medium,
        JSONExtractInt(s._airbyte_data, 'totalUsers') as total_users,
        JSONExtractInt(s._airbyte_data, 'sessions') as sessions,
        JSONExtractInt(s._airbyte_data, 'engagedSessions') as engaged_sessions,
        JSONExtractFloat(s._airbyte_data, 'engagementRate') as engagement_rate,
        JSONExtractFloat(s._airbyte_data, 'eventsPerSession') as events_per_session,
        JSONExtractInt(s._airbyte_data, 'eventCount') as event_count,
        JSONExtractFloat(s._airbyte_data, 'totalRevenue') as total_revenue,
        JSONExtractFloat(s._airbyte_data, 'userEngagementDuration') as user_engagement_duration_sec,
        s._airbyte_extracted_at                                             as _extracted_at,
        s._loaded_at                                                        as _loaded_at
    from source as s
    left join {{ ref('ga4_property_tenant') }} as m
        on JSONExtractString(s._airbyte_data, 'property_id') = m.property_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by property_id, date_day, source, medium
