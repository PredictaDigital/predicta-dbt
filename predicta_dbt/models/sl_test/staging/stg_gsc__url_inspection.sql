{#- Grain: project, connection, inspection date and page URL. One Search Console URL inspection result per page per day. Latest extract wins. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'gsc_pa_url_inspection') }}

),

typed as (

    select
        ifNull(c.customer_id, 'unmapped')   as customer_id,
        ifNull(c.project_id, 'unmapped')    as project_id,
        'gsc'                           as source_app_id,
        ifNull(c.connection_id, 'unmapped') as connection_id,
        JSONExtractString(s._airbyte_data, 'site_url')                            as source_account_id,
        toDate(JSONExtractString(s._airbyte_data, 'inspected_date')) as date,
        {{ sl_normalize_url("JSONExtractString(s._airbyte_data, 'inspect_url')") }} as page_url,
        JSONExtractString(s._airbyte_data, 'verdict') as verdict,
        toInt64(JSONExtractString(s._airbyte_data, 'verdict') = 'PASS') as passed,
        JSONExtractString(s._airbyte_data, 'coverage_state') as coverage_state,
        JSONExtractString(s._airbyte_data, 'indexing_state') as indexing_state,
        JSONExtractString(s._airbyte_data, 'robots_txt_state') as robots_txt_state,
        JSONExtractString(s._airbyte_data, 'page_fetch_state') as page_fetch_state,
        JSONExtractString(s._airbyte_data, 'mobile_usability_verdict') as mobile_usability_verdict,
        JSONExtractString(s._airbyte_data, 'rich_results_verdict') as rich_results_verdict,
        JSONExtractString(s._airbyte_data, 'google_canonical') as google_canonical,
        JSONExtractString(s._airbyte_data, 'user_canonical') as user_canonical,
        s._airbyte_extracted_at             as _extracted_at,
        s._loaded_at                        as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'gsc') as c
        on JSONExtractString(s._airbyte_data, 'site_url') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, page_url
