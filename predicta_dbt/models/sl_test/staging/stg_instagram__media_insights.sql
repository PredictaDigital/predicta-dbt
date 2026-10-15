{#- Grain: project, connection, snapshot day, media item and metric. Handles both stream layouts (older wide rows and newer one-row-per-metric rows); latest extract wins. -#}

with source as (

    select _airbyte_extracted_at, _loaded_at,
               '' as account_id, JSONExtractString(_airbyte_data, 'media_id') as media_id, JSONExtractString(_airbyte_data, 'metric') as metric,
               {{ sl_snapshot_date("JSONExtractString(_airbyte_data, 'synced_date')", '_airbyte_extracted_at') }} as date,
               {{ sl_metric_value("JSONExtractRaw(_airbyte_data, 'value')") }} as value
        from {{ source('sl_raw_pa', 'instagram_pa_media_insights') }}
        where JSONHas(_airbyte_data, 'metric')
        union all
        select _airbyte_extracted_at, _loaded_at, '' as account_id, JSONExtractString(_airbyte_data, 'id') as media_id, m.1 as metric,
               toDate(fromUnixTimestamp64Milli(toInt64(_airbyte_extracted_at), 'UTC')) as date, toFloat64(m.2) as value
        from {{ source('sl_raw_pa', 'instagram_pa_media_insights') }}
        array join [('reach', JSONExtractFloat(_airbyte_data, 'reach')), ('saved', JSONExtractFloat(_airbyte_data, 'saved')),
                    ('likes', JSONExtractFloat(_airbyte_data, 'likes')), ('comments', JSONExtractFloat(_airbyte_data, 'comments')),
                    ('shares', JSONExtractFloat(_airbyte_data, 'shares')), ('follows', JSONExtractFloat(_airbyte_data, 'follows')),
                    ('profile_visits', JSONExtractFloat(_airbyte_data, 'profile_visits'))] as m
        where NOT JSONHas(_airbyte_data, 'metric')

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'instagram'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(s.account_id, ''), {{ sl_sole_account('instagram') }})                            as source_account_id,
        s.date as date,
        s.media_id as media_id,
        s.metric as metric,
        s.value as value,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'instagram') as c
        on coalesce(nullif(s.account_id, ''), {{ sl_sole_account('instagram') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, media_id, metric
