{#- Grain: project, connection and snapshot day. The stream has no organisation id, so rows belong to the only LinkedIn connection. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'linkedin_pa_total_follower_count') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'linkedin'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'organization_id'), ''), {{ sl_sole_account('linkedin') }})                            as source_account_id,
        {{ sl_snapshot_date("JSONExtractString(s._airbyte_data, 'synced_date')", 's._airbyte_extracted_at') }} as date,
        JSONExtractInt(s._airbyte_data, 'firstDegreeSize') as first_degree_size,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'linkedin') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'organization_id'), ''), {{ sl_sole_account('linkedin') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date
