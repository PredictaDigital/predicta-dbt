{#- Grain: project, connection and snapshot day. Combines the 'profile' and 'users' streams; latest extract wins. -#}

with source as (

    select _airbyte_extracted_at, _loaded_at, _airbyte_data from {{ source('sl_raw_pa', 'instagram_pa_profile') }}
        union all
        select _airbyte_extracted_at, _loaded_at, _airbyte_data from {{ source('sl_raw_pa', 'instagram_pa_users') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'instagram'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'id'), ''), {{ sl_sole_account('instagram') }})                            as source_account_id,
        {{ sl_snapshot_date("JSONExtractString(s._airbyte_data, 'synced_date')", 's._airbyte_extracted_at') }} as date,
        JSONExtractString(s._airbyte_data, 'username') as username,
        JSONExtractInt(s._airbyte_data, 'followers_count') as followers_count,
        JSONExtractInt(s._airbyte_data, 'follows_count') as follows_count,
        JSONExtractInt(s._airbyte_data, 'media_count') as media_count,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'instagram') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'id'), ''), {{ sl_sole_account('instagram') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date
