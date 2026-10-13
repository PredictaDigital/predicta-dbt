{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='project_id'
) }}

{#- One row per project. project_id is the isolation boundary; it carries the
    owning customer_id (the access scope). Built from the sl_projects seed. -#}

select
    toLowCardinality(project_id)    as project_id,
    toLowCardinality(customer_id)   as customer_id,
    project_name,
    customer_name
from {{ ref('sl_projects') }}
