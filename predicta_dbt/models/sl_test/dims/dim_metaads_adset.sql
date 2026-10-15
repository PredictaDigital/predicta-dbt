{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    adset_id,
    argMax(adset_name, _extracted_at) as adset_name
from {{ ref('stg_metaads__adsets') }}
group by project_id, connection_id, adset_id
