{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='report_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Grain: project, connection, date, page_key, device strategy (one Lighthouse run).
    Scores and timings are point-in-time measurements, not sums: the semantic layer
    averages them. `runs` is 1 per row so an average can be weighted correctly. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'page_url', 'strategy']) }} as report_daily_key,
    toLowCardinality(customer_id)       as customer_id,
    toLowCardinality(project_id)        as project_id,
    toLowCardinality(source_app_id)     as source_app_id,
    toLowCardinality(connection_id)     as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    sipHash64(project_id, page_url)     as page_key,
    toLowCardinality(strategy)          as strategy,
    toInt64(1)                          as runs,
    performance_score,
    accessibility_score,
    best_practices_score,
    seo_score,
    first_contentful_paint_ms,
    speed_index_ms,
    largest_contentful_paint_ms,
    time_to_interactive_ms,
    total_blocking_time_ms,
    cumulative_layout_shift,
    _loaded_at
from {{ ref('stg_lighthouse__report') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
