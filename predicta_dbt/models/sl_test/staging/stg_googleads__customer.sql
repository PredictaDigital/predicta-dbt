{#- Grain: project, connection and Google Ads account. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'googleads_pa_customer') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'googleads'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        JSONExtractString(s._airbyte_data, 'customer.id')                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'customer.id') as account_id,
        JSONExtractString(s._airbyte_data, 'customer.descriptive_name') as customer_name,
        JSONExtractString(s._airbyte_data, 'customer.currency_code') as currency,
        JSONExtractString(s._airbyte_data, 'customer.time_zone') as time_zone,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'googleads') as c
        on JSONExtractString(s._airbyte_data, 'customer.id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, account_id
