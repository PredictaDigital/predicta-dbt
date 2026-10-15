{#- Grain: project, connection and organisation. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'linkedin_pa_organization_lookup') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'linkedin'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        JSONExtractString(s._airbyte_data, 'id')                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'id') as organization_id,
        JSONExtractString(s._airbyte_data, 'localizedName') as organization_name,
        JSONExtractString(s._airbyte_data, 'vanityName') as vanity_name,
        JSONExtractString(s._airbyte_data, 'organizationType') as organization_type,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'linkedin') as c
        on JSONExtractString(s._airbyte_data, 'id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, organization_id
