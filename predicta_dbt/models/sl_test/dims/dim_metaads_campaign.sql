{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    campaign_id,
    argMax(campaign_name, _extracted_at) as campaign_name
from {{ ref('stg_metaads__campaigns') }}
group by project_id, connection_id, campaign_id
