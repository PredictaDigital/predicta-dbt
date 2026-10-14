{#- Grain: project, connection and post. Combines the 'post' and 'posts' streams; latest extract wins. -#}

with source as (

    select _airbyte_extracted_at, _loaded_at, _airbyte_data from {{ source('sl_raw_pa', 'facebook_pa_post') }}
        union all
        select _airbyte_extracted_at, _loaded_at, _airbyte_data from {{ source('sl_raw_pa', 'facebook_pa_posts') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'facebook'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        splitByChar('_', JSONExtractString(s._airbyte_data, 'id'))[1]                            as source_account_id,
        JSONExtractString(s._airbyte_data, 'id') as post_id,
        toDate(substring(JSONExtractString(s._airbyte_data, 'created_time'), 1, 10)) as created_date,
        substring(JSONExtractString(s._airbyte_data, 'message'), 1, 500) as message,
        JSONExtractString(s._airbyte_data, 'status_type') as status_type,
        JSONExtractString(s._airbyte_data, 'permalink_url') as permalink_url,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'facebook') as c
        on splitByChar('_', JSONExtractString(s._airbyte_data, 'id'))[1] = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, post_id
