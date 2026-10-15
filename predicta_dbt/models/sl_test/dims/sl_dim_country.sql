{{ config(
    materialized='table',
    alias='dim_country',
    engine='MergeTree()',
    order_by='country'
) }}

select
    country,
    upper(country) as country_label
from (
    select distinct country from {{ ref('stg_gsc__search_all_fields') }}
    union distinct
    select distinct country from {{ ref('stg_gsc__search_by_country') }}
)
