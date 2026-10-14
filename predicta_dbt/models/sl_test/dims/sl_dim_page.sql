{{ config(
    materialized='table',
    alias='dim_page',
    engine='MergeTree()',
    order_by='(project_id, page_key)'
) }}

{#- One row per project and normalised page URL, from every source that reports
    pages (GA4, Search Console, Lighthouse). page_key = sipHash64(project_id,
    normalised URL), the same expression the facts use. Join facts to this table
    on project_id AND page_key. -#}

with urls as (

    select project_id, page_url from {{ ref('stg_ga4__pages') }}
    union all
    select project_id, page_url from {{ ref('stg_gsc__search_by_page') }}
    union all
    select project_id, page_url from {{ ref('stg_lighthouse__report') }}
    union all
    select project_id, page_url from {{ ref('stg_lighthouse__audit') }}

)

select
    toLowCardinality(project_id)        as project_id,
    sipHash64(project_id, page_url)     as page_key,
    page_url,
    domain(page_url)                    as host,
    path(page_url)                      as path
from (select distinct project_id, page_url from urls)
