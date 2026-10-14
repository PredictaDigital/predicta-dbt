{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    sitemap_path, is_pending, is_sitemap_index, last_submitted, last_downloaded, errors, warnings
from {{ ref('stg_gsc__sitemaps') }}
