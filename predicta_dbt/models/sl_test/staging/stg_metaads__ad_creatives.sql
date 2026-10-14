{#- Grain: project, connection and creative. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'metaads_pa_ad_creatives') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'metaads'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(replaceOne(JSONExtractString(s._airbyte_data, 'account_id'), 'act_', ''), ''), {{ sl_sole_account('metaads') }})                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'id') as creative_id,
        JSONExtractString(s._airbyte_data, 'name') as creative_name,
        JSONExtractString(s._airbyte_data, 'title') as title,
        substring(JSONExtractString(s._airbyte_data, 'body'), 1, 300) as body,
        JSONExtractString(s._airbyte_data, 'object_type') as object_type,
        JSONExtractString(s._airbyte_data, 'status') as status,
        JSONExtractString(s._airbyte_data, 'call_to_action_type') as call_to_action_type,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'metaads') as c
        on coalesce(nullif(replaceOne(JSONExtractString(s._airbyte_data, 'account_id'), 'act_', ''), ''), {{ sl_sole_account('metaads') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, creative_id
