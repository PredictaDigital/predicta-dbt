{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    ad_id,
    argMax(ad_name, _extracted_at) as ad_name
from {{ ref('stg_metaads__ads') }}
group by project_id, connection_id, ad_id
