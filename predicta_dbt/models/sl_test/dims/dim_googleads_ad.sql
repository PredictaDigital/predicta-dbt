{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select distinct
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    toLowCardinality(ad_id) as ad_id,
    toLowCardinality(ad_group_id) as ad_group_id,
    ad_type
from {{ ref('stg_googleads__ad_performance') }}
