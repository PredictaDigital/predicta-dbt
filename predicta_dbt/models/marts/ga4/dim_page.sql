{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(tenant_id, page_key)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- One row per tenant and page path. Tenant-owned, so it carries tenant_id.
    Fed by both the event-level and the report-level (Airbyte) GA4 staging models
    so one conformed dimension serves every fact. -#}

select
    tenant_id,
    {{ dbt_utils.generate_surrogate_key(['tenant_id', 'page_path']) }} as page_key,
    page_path,
    any(page_host)                                                       as page_host
from (
    select
        tenant_id,
        path(page_location)      as page_path,
        domain(page_location)    as page_host
    from {{ ref('stg_ga4__events') }}

    union all

    select tenant_id, page_path, host_name as page_host
    from {{ ref('stg_ga4_lc__pages') }}
)
group by tenant_id, page_path
