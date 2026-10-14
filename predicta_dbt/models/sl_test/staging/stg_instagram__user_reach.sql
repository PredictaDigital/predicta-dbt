{#- Grain: project, connection and day. Only rows that carry a date are used (older syncs held identifiers only). Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'instagram_pa_user_insights') }} where JSONHas(_airbyte_data, 'date')

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'instagram'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'business_account_id'), ''), {{ sl_sole_account('instagram') }})                            as source_account_id,
        toDate(substring(JSONExtractString(s._airbyte_data, 'date'), 1, 10)) as date,
        JSONExtractFloat(s._airbyte_data, 'reach') as reach,
        JSONExtractFloat(s._airbyte_data, 'reach_days_28') as reach_days_28,
        JSONExtractFloat(s._airbyte_data, 'reach_week') as reach_week,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'instagram') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'business_account_id'), ''), {{ sl_sole_account('instagram') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date
