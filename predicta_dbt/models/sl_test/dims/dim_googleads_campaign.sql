{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    toLowCardinality(campaign_id) as campaign_id,
    campaign_name, campaign_status, channel_type
from {{ ref('stg_googleads__campaigns') }}
