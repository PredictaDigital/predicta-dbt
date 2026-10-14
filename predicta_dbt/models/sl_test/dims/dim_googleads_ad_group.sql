{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    toLowCardinality(ad_group_id) as ad_group_id,
    toLowCardinality(campaign_id) as campaign_id,
    ad_group_name, ad_group_status
from {{ ref('stg_googleads__ad_groups') }}
