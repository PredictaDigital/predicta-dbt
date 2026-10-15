{#- Grain: project, connection and media item. Latest extract wins. Older syncs have no account id, so they belong to the only Instagram connection. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'instagram_pa_media') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'instagram'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'account_id'), ''), {{ sl_sole_account('instagram') }})                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'id') as media_id,
        substring(JSONExtractString(s._airbyte_data, 'caption'), 1, 300) as caption,
        JSONExtractString(s._airbyte_data, 'media_type') as media_type,
        JSONExtractString(s._airbyte_data, 'media_product_type') as media_product_type,
        JSONExtractString(s._airbyte_data, 'permalink') as permalink,
        toDate(substring(JSONExtractString(s._airbyte_data, 'timestamp'), 1, 10)) as posted_date,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'instagram') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'account_id'), ''), {{ sl_sole_account('instagram') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, media_id
