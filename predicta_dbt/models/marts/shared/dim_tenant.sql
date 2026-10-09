{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='tenant_id'
) }}

{#- One row per tenant, from the small synced tenant-metadata table. Deliberately
    NOT derived from any platform's staging model, so adding a platform never
    changes it. `timezone` is carried now so tenant-local reporting later
    only needs a change in to_reporting_date(). -#}

select
    tenant_id,
    tenant_name,
    timezone,
    plan,
    created_at
from {{ source('raw', 'tenants') }}
