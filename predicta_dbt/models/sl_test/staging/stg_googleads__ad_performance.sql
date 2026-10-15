{#- Grain: project, connection, day, campaign, ad group, ad, device and network. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'googleads_pa_ad_performance') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'googleads'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'customer.id'), ''), {{ sl_sole_account('googleads') }})                            as source_account_id,
        toDate(JSONExtractString(s._airbyte_data, 'segments.date')) as date,
        JSONExtractString(s._airbyte_data, 'campaign.id') as campaign_id,
        JSONExtractString(s._airbyte_data, 'ad_group.id') as ad_group_id,
        JSONExtractString(s._airbyte_data, 'ad_group_ad.ad.id') as ad_id,
        JSONExtractString(s._airbyte_data, 'ad_group_ad.ad.type') as ad_type,
        lowerUTF8(JSONExtractString(s._airbyte_data, 'segments.device')) as device,
        lowerUTF8(JSONExtractString(s._airbyte_data, 'segments.ad_network_type')) as network,
        JSONExtractInt(s._airbyte_data, 'metrics.impressions') as impressions,
        JSONExtractInt(s._airbyte_data, 'metrics.clicks') as clicks,
        JSONExtractInt(s._airbyte_data, 'metrics.cost_micros') as cost_micros,
        JSONExtractFloat(s._airbyte_data, 'metrics.conversions') as conversions,
        JSONExtractFloat(s._airbyte_data, 'metrics.conversions_value') as conversions_value,
        ifNull(nullif((select any(currency) from {{ ref('stg_googleads__customer') }}), ''), 'UNKNOWN') as currency,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'googleads') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'customer.id'), ''), {{ sl_sole_account('googleads') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, campaign_id, ad_group_id, ad_id, device, network
