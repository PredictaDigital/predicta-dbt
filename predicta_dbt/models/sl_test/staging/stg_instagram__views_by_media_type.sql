{#- Grain: project, connection, day and media product type. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'instagram_pa_views_by_media_type') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'instagram'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'account_id'), ''), {{ sl_sole_account('instagram') }})                            as source_account_id,
        toDate(substring(JSONExtractString(s._airbyte_data, 'date'), 1, 10)) as date,
        lowerUTF8(JSONExtractString(s._airbyte_data, 'media_product_type')) as media_product_type,
        JSONExtractFloat(s._airbyte_data, 'value') as views,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'instagram') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'account_id'), ''), {{ sl_sole_account('instagram') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, media_product_type
