{#- Grain: project, connection and Search Console property. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'gsc_pa_sites') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'gsc'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        JSONExtractString(s._airbyte_data, 'siteUrl')                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'siteUrl') as site_url,
        JSONExtractString(s._airbyte_data, 'permissionLevel') as permission_level,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'gsc') as c
        on JSONExtractString(s._airbyte_data, 'siteUrl') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, site_url
