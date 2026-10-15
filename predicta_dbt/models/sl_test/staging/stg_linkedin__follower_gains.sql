{#- Grain: project, connection and day. Follower gains for the organisation page. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'linkedin_pa_follower_statistics_time_bound') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'linkedin'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        replaceOne(JSONExtractString(s._airbyte_data, 'organizationalEntity'), 'urn:li:organization:', '')                            as source_account_id,
        toDate(fromUnixTimestamp64Milli(JSONExtractInt(s._airbyte_data, 'timeRangeStart'), 'UTC')) as date,
        JSONExtractInt(s._airbyte_data, 'followerGains', 'organicFollowerGain') as organic_follower_gain,
        JSONExtractInt(s._airbyte_data, 'followerGains', 'paidFollowerGain') as paid_follower_gain,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'linkedin') as c
        on replaceOne(JSONExtractString(s._airbyte_data, 'organizationalEntity'), 'urn:li:organization:', '') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date
