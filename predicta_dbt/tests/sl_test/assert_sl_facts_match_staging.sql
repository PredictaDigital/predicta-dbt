{{ config(tags=['sl_test']) }}
{#- Gate (D8): every fact measure must equal the deduplicated staging total, so no
    row is lost or double counted by key collapsing or incremental merges.
    Returns one row per mismatching measure; zero rows means all totals agree.
    Compared in whole numbers or to 0.001 for float measures. -#}

select check_name, fact_total, staging_total
from (
    select 'ga4 traffic sessions' as check_name,
           (select sum(sessions) from {{ ref('fct_ga4__traffic_daily') }}) as fact_total,
           (select sum(sessions) from {{ ref('stg_ga4__traffic_sources') }}) as staging_total
    union all select 'ga4 traffic engaged_sessions',
           (select sum(engaged_sessions) from {{ ref('fct_ga4__traffic_daily') }}),
           (select sum(engaged_sessions) from {{ ref('stg_ga4__traffic_sources') }})
    union all select 'ga4 traffic pageviews',
           (select sum(pageviews) from {{ ref('fct_ga4__traffic_daily') }}),
           (select sum(pageviews) from {{ ref('stg_ga4__traffic_sources') }})
    union all select 'ga4 page pageviews',
           (select sum(pageviews) from {{ ref('fct_ga4__page_daily') }}),
           (select sum(pageviews) from {{ ref('stg_ga4__pages') }})
    union all select 'gsc site clicks',
           (select sum(clicks) from {{ ref('fct_gsc__site_daily') }}),
           (select sum(clicks) from {{ ref('stg_gsc__search_by_date') }})
    union all select 'gsc site impressions',
           (select sum(impressions) from {{ ref('fct_gsc__site_daily') }}),
           (select sum(impressions) from {{ ref('stg_gsc__search_by_date') }})
    union all select 'gsc page clicks',
           (select sum(clicks) from {{ ref('fct_gsc__page_daily') }}),
           (select sum(clicks) from {{ ref('stg_gsc__search_by_page') }})
    union all select 'gsc page impressions',
           (select sum(impressions) from {{ ref('fct_gsc__page_daily') }}),
           (select sum(impressions) from {{ ref('stg_gsc__search_by_page') }})
    union all select 'gsc device clicks',
           (select sum(clicks) from {{ ref('fct_gsc__device_daily') }}),
           (select sum(clicks) from {{ ref('stg_gsc__search_by_device') }})
    union all select 'gsc query clicks',
           (select sum(clicks) from {{ ref('fct_gsc__query_daily') }}),
           (select sum(clicks) from {{ ref('stg_gsc__search_by_query') }})
    union all select 'gsc query impressions',
           (select sum(impressions) from {{ ref('fct_gsc__query_daily') }}),
           (select sum(impressions) from {{ ref('stg_gsc__search_by_query') }})
    union all select 'lighthouse report runs',
           (select sum(runs) from {{ ref('fct_lighthouse__report_daily') }}),
           (select toInt64(count()) from {{ ref('stg_lighthouse__report') }})
    union all select 'lighthouse audit rows',
           (select toInt64(count()) from {{ ref('fct_lighthouse__audit_daily') }}),
           (select toInt64(count()) from {{ ref('stg_lighthouse__audit') }})
)
where abs(fact_total - staging_total) > 0.001
