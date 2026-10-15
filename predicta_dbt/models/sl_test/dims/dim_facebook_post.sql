{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    sipHash64(project_id, post_id) as post_key,
    post_id, created_date, message, status_type, permalink_url
from {{ ref('stg_facebook__post') }}
