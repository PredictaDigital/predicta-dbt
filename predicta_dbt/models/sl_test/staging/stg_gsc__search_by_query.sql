{#- Grain: one row per project, connection, date, search type and search query.
    Latest extract wins. sum_position = position x impressions, so it adds up
    across rows. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'gsc_pa_search_analytics_by_query') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')                                           as customer_id,
        ifNull(c.project_id, 'unmapped')                                            as project_id,
        'gsc'                                                                       as source_app_id,
        ifNull(c.connection_id, 'unmapped')                                         as connection_id,
        JSONExtractString(s._airbyte_data, 'site_url')                              as source_account_id,
        toDate(JSONExtractString(s._airbyte_data, 'date'))                          as date,
        JSONExtractString(s._airbyte_data, 'search_type')                           as search_type,
        JSONExtractString(s._airbyte_data, 'query')                                 as query,
        JSONExtractInt(s._airbyte_data, 'clicks')                                   as clicks,
        JSONExtractInt(s._airbyte_data, 'impressions')                              as impressions,
        if(JSONHas(s._airbyte_data, 'position'),
           JSONExtractFloat(s._airbyte_data, 'position')
               * JSONExtractInt(s._airbyte_data, 'impressions'), 0)                 as sum_position,
        if(JSONHas(s._airbyte_data, 'position'),
           JSONExtractInt(s._airbyte_data, 'impressions'), 0)                       as position_impressions,
        s._airbyte_extracted_at                                                     as _extracted_at,
        s._loaded_at                                                                as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'gsc') as c
        on JSONExtractString(s._airbyte_data, 'site_url') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, search_type, query
