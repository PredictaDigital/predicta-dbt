{#- Grain: project, connection and campaign. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'googleads_pa_campaign_details') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'googleads'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'customer.id'), ''), {{ sl_sole_account('googleads') }})                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'campaign.id') as campaign_id,
        JSONExtractString(s._airbyte_data, 'campaign.name') as campaign_name,
        JSONExtractString(s._airbyte_data, 'campaign.status') as campaign_status,
        JSONExtractString(s._airbyte_data, 'campaign.advertising_channel_type') as channel_type,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'googleads') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'customer.id'), ''), {{ sl_sole_account('googleads') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, campaign_id
