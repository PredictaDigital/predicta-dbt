{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='inspection_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- One Search Console URL inspection per page and day: whether Google indexed the page and any problems found. -#}

select
    {{ dbt_utils.generate_surrogate_key(['project_id', 'connection_id', 'date', 'page_url', 'verdict', 'coverage_state', 'indexing_state', 'robots_txt_state', 'page_fetch_state', 'mobile_usability_verdict', 'rich_results_verdict']) }} as inspection_daily_key,
    toLowCardinality(customer_id)        as customer_id,
    toLowCardinality(project_id)         as project_id,
    toLowCardinality(source_app_id)      as source_app_id,
    toLowCardinality(connection_id)      as connection_id,
    toLowCardinality(source_account_id)  as source_account_id,
    date,
    sipHash64(project_id, page_url) as page_key,
    toLowCardinality(verdict) as verdict,
    toLowCardinality(coverage_state) as coverage_state,
    toLowCardinality(indexing_state) as indexing_state,
    toLowCardinality(robots_txt_state) as robots_txt_state,
    toLowCardinality(page_fetch_state) as page_fetch_state,
    toLowCardinality(mobile_usability_verdict) as mobile_usability_verdict,
    toLowCardinality(rich_results_verdict) as rich_results_verdict,
    toInt64(1) as inspections,
    passed,
    _loaded_at
from {{ ref('stg_gsc__url_inspection') }}
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
