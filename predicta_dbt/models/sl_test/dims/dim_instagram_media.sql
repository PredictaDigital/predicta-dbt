{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    sipHash64(project_id, media_id) as media_key,
    media_id, caption, media_type, media_product_type, permalink, posted_date
from {{ ref('stg_instagram__media') }}
