{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='location_key'
) }}

{#- Global (not tenant-owned): a city is the same place for every customer. -#}

select
    {{ dbt_utils.generate_surrogate_key(['country', 'region', 'city']) }} as location_key,
    country,
    region,
    city
from (
    select distinct country, region, city
    from {{ ref('stg_ga4_lc__locations') }}
)
