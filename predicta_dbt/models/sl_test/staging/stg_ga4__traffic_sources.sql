{#- Grain: one row per project, connection, date, session source and session medium.
    Airbyte re-pulls a rolling window each sync, so the same key can arrive several
    times, sometimes restated. Keep the latest extract (never rely on merge-time
    dedup). Engaged sessions are derived: sessions x (1 - bounce rate). -#}

with source as (

    select * from {{ source('sl_raw_pa', 'ga4_pa_traffic_sources') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')                                              as customer_id,
        ifNull(c.project_id, 'unmapped')                                               as project_id,
        'ga4'                                                                          as source_app_id,
        ifNull(c.connection_id, 'unmapped')                                            as connection_id,
        JSONExtractString(s._airbyte_data, 'property_id')                              as source_account_id,
        toDate(parseDateTimeBestEffort(JSONExtractString(s._airbyte_data, 'date')))    as date,
        JSONExtractString(s._airbyte_data, 'sessionSource')                            as source,
        JSONExtractString(s._airbyte_data, 'sessionMedium')                            as medium,
        JSONExtractInt(s._airbyte_data, 'sessions')                                    as sessions,
        toInt64(round(JSONExtractInt(s._airbyte_data, 'sessions')
                      * (1 - JSONExtractFloat(s._airbyte_data, 'bounceRate'))))        as engaged_sessions,
        JSONExtractInt(s._airbyte_data, 'totalUsers')                                  as total_users,
        JSONExtractInt(s._airbyte_data, 'newUsers')                                    as new_users,
        JSONExtractInt(s._airbyte_data, 'screenPageViews')                             as pageviews,
        JSONExtractFloat(s._airbyte_data, 'averageSessionDuration')
            * JSONExtractInt(s._airbyte_data, 'sessions')                              as session_duration_sec,
        s._airbyte_extracted_at                                                        as _extracted_at,
        s._loaded_at                                                                   as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'ga4') as c
        on JSONExtractString(s._airbyte_data, 'property_id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, source, medium
