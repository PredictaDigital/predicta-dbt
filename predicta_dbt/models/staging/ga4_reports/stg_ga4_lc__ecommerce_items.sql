{#- Grain: one row per property, date and item name.
    Airbyte re-pulls a rolling date window each sync, so the same natural key
    arrives in several files. Keep the latest sync (highest _airbyte_extracted_at).
    Responsibilities: unpack JSON, type, rename, map tenant, dedupe. -#}

with source as (

    select * from {{ source('raw_ga4_lc', 'ga4_lc_ecommerce_purchases_item_name_report') }}

),

typed as (

    select
        ifNull(m.tenant_id, 'unmapped')                                     as tenant_id,
        JSONExtractString(s._airbyte_data, 'property_id')                   as property_id,
        toDate(parseDateTimeBestEffort(JSONExtractString(s._airbyte_data, 'date'))) as date_day,
        JSONExtractString(s._airbyte_data, 'itemName') as item_name,
        JSONExtractInt(s._airbyte_data, 'itemsViewed') as items_viewed,
        JSONExtractInt(s._airbyte_data, 'itemsAddedToCart') as items_added_to_cart,
        JSONExtractInt(s._airbyte_data, 'itemsPurchased') as items_purchased,
        JSONExtractFloat(s._airbyte_data, 'itemRevenue') as item_revenue,
        JSONExtractFloat(s._airbyte_data, 'cartToViewRate') as cart_to_view_rate,
        JSONExtractFloat(s._airbyte_data, 'purchaseToViewRate') as purchase_to_view_rate,
        s._airbyte_extracted_at                                             as _extracted_at,
        s._loaded_at                                                        as _loaded_at
    from source as s
    left join {{ ref('ga4_property_tenant') }} as m
        on JSONExtractString(s._airbyte_data, 'property_id') = m.property_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by property_id, date_day, item_name
