{#- Grain: one row per project, connection, URL, device strategy and fetch date.
    One Lighthouse run per day per URL and strategy; latest extract wins.
    Category scores are 0 to 100 (as Lighthouse reports them here). Timings arrive as
    display strings ("2.6 s", "0 ms") and are converted to milliseconds. Cumulative
    layout shift is unitless. -#}

with source as (

    select * from {{ source('sl_raw_pa', 'lighthouse_pa_lighthouse_report') }}

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
        JSONExtractFloat(s._airbyte_data, 'performance_score')                      as performance_score,
        JSONExtractFloat(s._airbyte_data, 'accessibility_score')                    as accessibility_score,
        JSONExtractFloat(s._airbyte_data, 'best_practices_score')                   as best_practices_score,
        JSONExtractFloat(s._airbyte_data, 'seo_score')                              as seo_score,
        {{ sl_lighthouse_ms('s._airbyte_data', 'first_contentful_paint') }} as first_contentful_paint_ms,
        {{ sl_lighthouse_ms('s._airbyte_data', 'speed_index') }} as speed_index_ms,
        {{ sl_lighthouse_ms('s._airbyte_data', 'largest_contentful_paint') }} as largest_contentful_paint_ms,
        {{ sl_lighthouse_ms('s._airbyte_data', 'time_to_interactive') }} as time_to_interactive_ms,
        {{ sl_lighthouse_ms('s._airbyte_data', 'total_blocking_time') }} as total_blocking_time_ms,
        JSONExtractFloat(s._airbyte_data, 'cumulative_layout_shift')                as cumulative_layout_shift,
        s._airbyte_extracted_at                                                     as _extracted_at,
        s._loaded_at                                                                as _loaded_at
    from source as s
    left join (select * from {{ ref('sl_connections') }} where source_app_id = 'lighthouse') as c
        on JSONExtractString(s._airbyte_data, 'user_website_id') = c.source_account_id

)

select *
from typed
order by _extracted_at desc, _loaded_at desc
limit 1 by project_id, connection_id, date, page_url, strategy
