{#- Grain: project, connection and snapshot day. Newer syncs carry only id and name; the dimension keeps the latest non-empty currency. Latest extract wins per day. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'metaads_pa_ad_account') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'metaads'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        replaceOne(JSONExtractString(s._airbyte_data, 'id'), 'act_', '')                            as source_account_id,
        {{ sl_snapshot_date("JSONExtractString(s._airbyte_data, 'synced_date')", 's._airbyte_extracted_at') }} as date,
        JSONExtractString(s._airbyte_data, 'name') as account_name,
        JSONExtractString(s._airbyte_data, 'currency') as currency,
        JSONExtractInt(s._airbyte_data, 'amount_spent') as amount_spent,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'metaads') as c
        on replaceOne(JSONExtractString(s._airbyte_data, 'id'), 'act_', '') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date
