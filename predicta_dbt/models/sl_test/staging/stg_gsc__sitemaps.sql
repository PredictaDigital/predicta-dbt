{#- Grain: project, connection and sitemap. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'gsc_pa_sitemaps') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'gsc'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        coalesce(nullif(JSONExtractString(s._airbyte_data, 'site_url'), ''), {{ sl_sole_account('gsc') }})                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'path') as sitemap_path,
        toUInt8(JSONExtractBool(s._airbyte_data, 'isPending')) as is_pending,
        toUInt8(JSONExtractBool(s._airbyte_data, 'isSitemapsIndex')) as is_sitemap_index,
        JSONExtractString(s._airbyte_data, 'lastSubmitted') as last_submitted,
        JSONExtractString(s._airbyte_data, 'lastDownloaded') as last_downloaded,
        toInt64OrZero(JSONExtractString(s._airbyte_data, 'errors')) as errors,
        toInt64OrZero(JSONExtractString(s._airbyte_data, 'warnings')) as warnings,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'gsc') as c
        on coalesce(nullif(JSONExtractString(s._airbyte_data, 'site_url'), ''), {{ sl_sole_account('gsc') }}) = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, sitemap_path
