{#- Grain: one row per project, connection, URL, device strategy, fetch date and
    audit id. Latest extract wins. score is 0 to 1 (1 = pass); an audit with no
    score is stored as -1 so the column is never Nullable. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'lighthouse_pa_lighthouse_audit') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')                                           as customer_id,
        ifNull(c.project_id, 'unmapped')                                            as project_id,
        'lighthouse'                                                                as source_app_id,
        ifNull(c.connection_id, 'unmapped')                                         as connection_id,
        JSONExtractString(s._airbyte_data, 'user_website_id')                       as source_account_id,
        toDate(JSONExtractString(s._airbyte_data, 'fetch_date'))                    as date,
        {{ sl_normalize_url("JSONExtractString(s._airbyte_data, 'url')") }}         as page_url,
        lowerUTF8(JSONExtractString(s._airbyte_data, 'strategy'))                   as strategy,
        JSONExtractString(s._airbyte_data, 'id')                                    as audit_id,
        JSONExtractString(s._airbyte_data, 'title')                                 as audit_title,
        JSONExtractString(s._airbyte_data, 'description')                           as audit_description,
        if(JSONHas(s._airbyte_data, 'score') AND JSONType(s._airbyte_data, 'score') != 'Null',
           JSONExtractFloat(s._airbyte_data, 'score'), -1)                          as score,
        s._airbyte_extracted_at                                                     as _extracted_at,
        s._loaded_at                                                                as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'lighthouse') as c
        on JSONExtractString(s._airbyte_data, 'user_website_id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, page_url, strategy, audit_id
