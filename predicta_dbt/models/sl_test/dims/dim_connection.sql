{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id, connection_id)'
) }}

{#- One row per source connection: which project it belongs to, which app it
    reads (ga4, gsc, lighthouse) and the account inside that app (GA4 property,
    Search Console site, Lighthouse website). source_app_id is lineage, never a
    tenant key. Built from the sl_connections seed. -#}

select
    toLowCardinality(connection_id)     as connection_id,
    toLowCardinality(project_id)        as project_id,
    toLowCardinality(customer_id)       as customer_id,
    toLowCardinality(source_app_id)     as source_app_id,
    source_account_id,
    connection_name
from {{ ref('sl_connections') }}
