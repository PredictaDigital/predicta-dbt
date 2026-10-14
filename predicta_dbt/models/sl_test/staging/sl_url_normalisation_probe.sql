{{ config(materialized='view') }}

{#- Test fixture, not a business model. Runs the real sl_normalize_url macro over
    URL variants that must collapse onto one canonical page, so check D7 can prove
    the normalisation without duplicating its logic. Each group holds variants of
    ONE page (tracking parameters, fragment, mixed case, trailing slash) plus one
    different page that must stay different. -#}

select page_group, raw_url, {{ sl_normalize_url('raw_url') }} as normalised_url
from (
    select 'about' as page_group, 'https://predictaanalytics.io/about/' as raw_url
    union all select 'about', 'https://predictaanalytics.io/about'
    union all select 'about', 'https://PredictaAnalytics.io/About/'
    union all select 'about', 'https://predictaanalytics.io/about/?utm_source=x&utm_medium=y'
    union all select 'about', 'https://predictaanalytics.io/about#team'
    union all select 'about', 'https://predictaanalytics.io/about/?utm_source=x#team'
    union all select 'home', 'https://predictaanalytics.io/'
    union all select 'home', 'https://predictaanalytics.io'
    union all select 'home', 'HTTPS://PREDICTAANALYTICS.IO/?gclid=abc'
    union all select 'other', 'https://predictaanalytics.io/about-us/'
)
