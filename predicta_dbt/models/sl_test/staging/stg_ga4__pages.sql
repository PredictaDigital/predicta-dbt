{#- Grain: one row per project, connection, date, host name and page path (with
    query string, as GA4 reports it). Latest extract wins. The URL is rebuilt as
    https://<host><path> and normalised; several raw paths (for example with
    tracking parameters) collapse to one page_key in the fact. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'ga4_pa_pages') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')                                              as customer_id,
        ifNull(c.project_id, 'unmapped')                                               as project_id,
        'ga4'                                                                          as source_app_id,
        ifNull(c.connection_id, 'unmapped')                                            as connection_id,
        JSONExtractString(s._airbyte_data, 'property_id')                              as source_account_id,
        toDate(parseDateTimeBestEffort(JSONExtractString(s._airbyte_data, 'date')))    as date,
        JSONExtractString(s._airbyte_data, 'hostName')                                 as host_name,
        JSONExtractString(s._airbyte_data, 'pagePathPlusQueryString')                  as path_with_query,
        {{ sl_normalize_url("concat('https://', JSONExtractString(s._airbyte_data, 'hostName'), JSONExtractString(s._airbyte_data, 'pagePathPlusQueryString'))") }} as page_url,
        JSONExtractInt(s._airbyte_data, 'screenPageViews')                             as pageviews,
        s._airbyte_extracted_at                                                        as _extracted_at,
        s._loaded_at                                                                   as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'ga4') as c
        on JSONExtractString(s._airbyte_data, 'property_id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, host_name, path_with_query
