{#- Grain: project, connection, day and page insight metric. Handles both stream layouts (the older nested 'values' list and the newer one-row-per-metric layout). Latest extract wins. -#}

with source as (

    select _airbyte_extracted_at, _loaded_at,
               JSONExtractString(_airbyte_data, 'page_id') as page_id, JSONExtractString(_airbyte_data, 'metric') as metric,
               toDate(substring(JSONExtractString(_airbyte_data, 'end_time'), 1, 10)) as date,
               {{ sl_metric_value("JSONExtractRaw(_airbyte_data, 'value')") }} as value
        from {{ source('sl_raw_pa', 'facebook_pa_page_insights') }}
        where JSONHas(_airbyte_data, 'metric')
        union all
        select _airbyte_extracted_at, _loaded_at,
               splitByChar('/', JSONExtractString(_airbyte_data, 'id'))[1] as page_id, JSONExtractString(_airbyte_data, 'name') as metric,
               toDate(substring(JSONExtractString(v, 'end_time'), 1, 10)) as date,
               {{ sl_metric_value("JSONExtractRaw(v, 'value')") }} as value
        from {{ source('sl_raw_pa', 'facebook_pa_page_insights') }}
        array join JSONExtractArrayRaw(_airbyte_data, 'values') as v
        where NOT JSONHas(_airbyte_data, 'metric')

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'facebook'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        s.page_id                            as source_account_id,
        s.date as date,
        s.metric as metric,
        s.value as value,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'facebook') as c
        on s.page_id = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, metric
