{#- Gate: fact measures must equal the deduplicated staging totals, so no row is
    lost or double counted by the rollups and incremental merges. -#}
select check_name, fact_total, staging_total
from (
    select 'page views (pages)' as check_name,
           (select sum(pageviews) from {{ ref('fact_page_daily') }})        as fact_total,
           (select sum(pageviews) from {{ ref('stg_ga4_lc__pages') }})      as staging_total
    union all
    select 'sessions (devices)',
           (select sum(sessions) from {{ ref('fact_device_daily') }}),
           (select sum(sessions) from {{ ref('stg_ga4_lc__devices') }})
    union all
    select 'sessions (locations)',
           (select sum(sessions) from {{ ref('fact_location_daily') }}),
           (select sum(sessions) from {{ ref('stg_ga4_lc__locations') }})
    union all
    select 'items purchased',
           (select sum(items_purchased) from {{ ref('fact_item_daily') }}),
           (select sum(items_purchased) from {{ ref('stg_ga4_lc__ecommerce_items') }})
    union all
    select 'sessions (site)',
           (select sum(sessions) from {{ ref('fact_site_daily') }}),
           (select sum(sessions) from {{ ref('stg_ga4_lc__website_overview') }})
    union all
    select 'engaged sessions (traffic)',
           (select sum(engaged_sessions) from {{ ref('fact_traffic_daily') }}),
           (select sum(engaged_sessions) from {{ ref('stg_ga4_lc__traffic_acquisition_source_medium') }})
)
where fact_total != staging_total
