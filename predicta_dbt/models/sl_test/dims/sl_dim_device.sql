{{ config(
    materialized='table',
    alias='dim_device',
    engine='MergeTree()',
    order_by='device'
) }}

{#- Shared reference: the device categories used by Search Console and Lighthouse
    (lower case). Lighthouse calls them strategies: mobile and desktop. -#}

select device, device_group
from (
    select 'desktop' as device, 'Computer' as device_group
    union all select 'mobile', 'Handheld'
    union all select 'tablet', 'Handheld'
)
