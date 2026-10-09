{#- Grain: one row per property, date, device category, OS and browser.
    Airbyte re-pulls a rolling date window each sync, so the same natural key
    arrives in several files. Keep the latest sync (highest _airbyte_extracted_at).
    Responsibilities: unpack JSON, type, rename, map tenant, dedupe. -#}

with source as (

    select * from {{ source('raw_ga4_lc', 'ga4_lc_devices') }}

),

typed as (

    select
        ifNull(m.tenant_id, 'unmapped')                                     as tenant_id,
        JSONExtractString(s._airbyte_data, 'property_id')                   as property_id,
        toDate(parseDateTimeBestEffort(JSONExtractString(s._airbyte_data, 'date'))) as date_day,
        JSONExtractString(s._airbyte_data, 'deviceCategory') as device_category,
        JSONExtractString(s._airbyte_data, 'operatingSystem') as operating_system,
        JSONExtractString(s._airbyte_data, 'browser') as browser,
        JSONExtractInt(s._airbyte_data, 'totalUsers') as total_users,
        JSONExtractInt(s._airbyte_data, 'newUsers') as new_users,
        JSONExtractInt(s._airbyte_data, 'sessions') as sessions,
        JSONExtractFloat(s._airbyte_data, 'sessionsPerUser') as sessions_per_user,
        JSONExtractFloat(s._airbyte_data, 'averageSessionDuration') as avg_session_duration_sec,
        JSONExtractInt(s._airbyte_data, 'screenPageViews') as pageviews,
        JSONExtractFloat(s._airbyte_data, 'screenPageViewsPerSession') as pageviews_per_session,
        JSONExtractFloat(s._airbyte_data, 'bounceRate') as bounce_rate,
        s._airbyte_extracted_at                                             as _extracted_at,
        s._loaded_at                                                        as _loaded_at
    from source as s
    left join {{ ref('ga4_property_tenant') }} as m
        on JSONExtractString(s._airbyte_data, 'property_id') = m.property_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by property_id, date_day, device_category, operating_system, browser
