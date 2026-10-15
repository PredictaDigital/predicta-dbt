{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select
    toLowCardinality(project_id) as project_id,
    toLowCardinality(connection_id) as connection_id,
    creative_id, creative_name, title, body, object_type, status, call_to_action_type
from {{ ref('stg_metaads__ad_creatives') }}
