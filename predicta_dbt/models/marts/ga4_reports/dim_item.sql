{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(tenant_id, item_key)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- One row per tenant and item name. Tenant-owned: each shop has its own catalogue. -#}

select
    tenant_id,
    {{ dbt_utils.generate_surrogate_key(['tenant_id', 'item_name']) }} as item_key,
    item_name
from (
    select distinct tenant_id, item_name
    from {{ ref('stg_ga4_lc__ecommerce_items') }}
)
