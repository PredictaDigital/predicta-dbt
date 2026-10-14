{#- Grain: project, connection and snapshot date: the page's follower and fan counts as they were that day. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'facebook_pa_page') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'facebook'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        JSONExtractString(s._airbyte_data, 'id')                            as source_account_id,
        {{ sl_snapshot_date("JSONExtractString(s._airbyte_data, 'synced_date')", 's._airbyte_extracted_at') }} as date,
        JSONExtractString(s._airbyte_data, 'name') as page_name,
        JSONExtractInt(s._airbyte_data, 'fan_count') as fan_count,
        JSONExtractInt(s._airbyte_data, 'followers_count') as followers_count,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'facebook') as c
        on JSONExtractString(s._airbyte_data, 'id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date
