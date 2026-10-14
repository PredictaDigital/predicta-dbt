{#- Grain: project, connection and LinkedIn Ads account. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'linkedinads_pa_accounts') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'linkedinads'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        JSONExtractString(s._airbyte_data, 'id')                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'id') as account_id,
        JSONExtractString(s._airbyte_data, 'name') as account_name,
        JSONExtractString(s._airbyte_data, 'currency') as currency,
        JSONExtractString(s._airbyte_data, 'status') as status,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'linkedinads') as c
        on JSONExtractString(s._airbyte_data, 'id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, account_id
