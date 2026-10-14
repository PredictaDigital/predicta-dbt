{#- Grain: project, connection, snapshot day, post and metric. Post metrics are lifetime totals, so each snapshot restates the running total. Handles both stream layouts; latest extract wins. -#}

with source as (

    select _airbyte_extracted_at, _loaded_at,
               JSONExtractString(_airbyte_data, 'post_id') as post_id, JSONExtractString(_airbyte_data, 'metric') as metric,
               {{ sl_snapshot_date("JSONExtractString(_airbyte_data, 'synced_date')", '_airbyte_extracted_at') }} as date,
               {{ sl_metric_value("JSONExtractRaw(_airbyte_data, 'value')") }} as value
        from {{ source('sl_raw_pa', 'facebook_pa_post_insights') }}
        where JSONHas(_airbyte_data, 'metric')
        union all
        select _airbyte_extracted_at, _loaded_at,
               splitByString('/insights/', JSONExtractString(_airbyte_data, 'id'))[1] as post_id, JSONExtractString(_airbyte_data, 'name') as metric,
               toDate(fromUnixTimestamp64Milli(toInt64(_airbyte_extracted_at), 'UTC')) as date,
               {{ sl_metric_value("JSONExtractRaw(JSONExtractArrayRaw(_airbyte_data, 'values')[1], 'value')") }} as value
        from {{ source('sl_raw_pa', 'facebook_pa_post_insights') }}
        where NOT JSONHas(_airbyte_data, 'metric')

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'facebook'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        splitByChar('_', s.post_id)[1]                            as source_account_id,
        s.date as date,
        s.post_id as post_id,
        s.metric as metric,
        s.value as value,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'facebook') as c
        on splitByChar('_', s.post_id)[1] = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, post_id, metric
