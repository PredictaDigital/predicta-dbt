{#- Grain: one row per property, date, host and path+query.
    Airbyte re-pulls a rolling date window each sync, so the same natural key
    arrives in several files. Keep the latest sync (highest _airbyte_extracted_at).
    Responsibilities: unpack JSON, type, rename, map tenant, dedupe. -#}

with source as (

    select * from {{ source('raw_ga4_lc', 'ga4_lc_pages') }}

),

typed as (

    select
        ifNull(m.tenant_id, 'unmapped')                                     as tenant_id,
        JSONExtractString(s._airbyte_data, 'property_id')                   as property_id,
        toDate(parseDateTimeBestEffort(JSONExtractString(s._airbyte_data, 'date'))) as date_day,
        JSONExtractString(s._airbyte_data, 'hostName') as host_name,
        JSONExtractString(s._airbyte_data, 'pagePathPlusQueryString') as path_with_query,
        if(splitByChar('?', JSONExtractString(s._airbyte_data, 'pagePathPlusQueryString'))[1] = '', '/', splitByChar('?', JSONExtractString(s._airbyte_data, 'pagePathPlusQueryString'))[1]) as page_path,
        JSONExtractInt(s._airbyte_data, 'screenPageViews') as pageviews,
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
limit 1 by property_id, date_day, host_name, path_with_query
