{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='device_key'
) }}

{#- Global (not tenant-owned): 'mobile' means the same for every customer.
    Fed by both event-level and report-level GA4 staging models. -#}

select
    {{ dbt_utils.generate_surrogate_key(['device_category']) }} as device_key,
    device_category
from (
    select distinct coalesce(nullIf(device_category, ''), 'unknown') as device_category
    from {{ ref('stg_ga4__events') }}

    union distinct

    select distinct coalesce(nullIf(device_category, ''), 'unknown') as device_category
    from {{ ref('stg_ga4_lc__devices') }}
)
