{#- Grain: project, connection, snapshot day and Meta campaign. The stream has no account id, so rows belong to the only Meta Ads connection. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'metaads_pa_campaigns') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'metaads'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'account_id'), ''), {{ sl_sole_account('metaads') }})                            as source_account_id,
        {{ sl_snapshot_date("JSONExtractString(s._airbyte_data, 'synced_date')", 's._airbyte_extracted_at') }} as date,
        JSONExtractString(s._airbyte_data, 'id') as campaign_id,
        JSONExtractString(s._airbyte_data, 'name') as campaign_name,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'metaads') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'account_id'), ''), {{ sl_sole_account('metaads') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, campaign_id
