{{ config(tags=['sl_test']) }}
{#- Gates D9 and D10: every mart must equal the sum of the source facts it unions, in original currency
    and in USD (tolerance 0.01), and the digital marketing mart must hold each source's own total.
    Returns one row per mismatch; zero rows means the marts agree with the facts. -#}

select check_name, mart_total, fact_total
from (
    select 'ppc impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('mart_ppc__campaign_daily') }})) as mart_total, toFloat64((select sum(impressions) from {{ ref('fct_googleads__performance_daily') }})) as fact_total
    union all select 'ppc clicks', toFloat64((select sum(clicks) from {{ ref('mart_ppc__campaign_daily') }})), toFloat64((select sum(clicks) from {{ ref('fct_googleads__performance_daily') }}))
    union all select 'ppc spend original', toFloat64((select sum(spend_original) from {{ ref('mart_ppc__campaign_daily') }})), toFloat64((select sum(spend) from {{ ref('fct_googleads__performance_daily') }}))
    union all select 'ppc spend usd', toFloat64((select sum(spend_usd) from {{ ref('mart_ppc__campaign_daily') }})), toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__performance_daily') }}))
    union all select 'ppc platform conversions', toFloat64((select sum(platform_conversions) from {{ ref('mart_ppc__campaign_daily') }})), toFloat64((select sum(conversions) from {{ ref('fct_googleads__performance_daily') }}))
    union all select 'seo clicks', toFloat64((select sum(clicks) from {{ ref('mart_seo__search_daily') }})), toFloat64((select sum(clicks) from {{ ref('fct_gsc__search_daily') }}))
    union all select 'seo impressions', toFloat64((select sum(impressions) from {{ ref('mart_seo__search_daily') }})), toFloat64((select sum(impressions) from {{ ref('fct_gsc__search_daily') }}))
    union all select 'seo sum_position', toFloat64((select sum(sum_position) from {{ ref('mart_seo__search_daily') }})), toFloat64((select sum(sum_position) from {{ ref('fct_gsc__search_daily') }}))
    union all select 'dm ga4_sessions', toFloat64((select sum(ga4_sessions) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(sessions) from {{ ref('fct_ga4__traffic_daily') }}))
    union all select 'dm ga4_engaged_sessions', toFloat64((select sum(ga4_engaged_sessions) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(engaged_sessions) from {{ ref('fct_ga4__traffic_daily') }}))
    union all select 'dm gsc_clicks', toFloat64((select sum(gsc_clicks) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(clicks) from {{ ref('fct_gsc__site_daily') }}))
    union all select 'dm gsc_impressions', toFloat64((select sum(gsc_impressions) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(impressions) from {{ ref('fct_gsc__site_daily') }}))
    union all select 'dm ppc_spend_usd', toFloat64((select sum(ppc_spend_usd) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(spend_usd) from {{ ref('mart_ppc__campaign_daily') }}))
    union all select 'dm ppc_clicks', toFloat64((select sum(ppc_clicks) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(clicks) from {{ ref('mart_ppc__campaign_daily') }}))
    union all select 'dm ppc_impressions', toFloat64((select sum(ppc_impressions) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(impressions) from {{ ref('mart_ppc__campaign_daily') }}))
    union all select 'dm platform_conversions', toFloat64((select sum(platform_conversions) from {{ ref('mart_dm__channel_daily') }})), toFloat64((select sum(platform_conversions) from {{ ref('mart_ppc__campaign_daily') }}))
    union all select 'smm fb_page_views', toFloat64((select sum(fb_page_views) from {{ ref('mart_smm__social_daily') }})), toFloat64((select sum(page_views_total) from {{ ref('fct_facebook__page_insights_daily') }}))
    union all select 'smm fb_post_engagements', toFloat64((select sum(fb_post_engagements) from {{ ref('mart_smm__social_daily') }})), toFloat64((select sum(page_post_engagements) from {{ ref('fct_facebook__page_insights_daily') }}))
    union all select 'smm ig_views', toFloat64((select sum(ig_views) from {{ ref('mart_smm__social_daily') }})), toFloat64((select sum(views) from {{ ref('fct_instagram__account_daily') }}))
    union all select 'smm ig_total_interactions', toFloat64((select sum(ig_total_interactions) from {{ ref('mart_smm__social_daily') }})), toFloat64((select sum(total_interactions) from {{ ref('fct_instagram__account_daily') }}))
    union all select 'smm li_impressions', toFloat64((select sum(li_impressions) from {{ ref('mart_smm__social_daily') }})), toFloat64((select sum(impressions) from {{ ref('fct_linkedin__share_daily') }}))
    union all select 'smm li_clicks', toFloat64((select sum(li_clicks) from {{ ref('mart_smm__social_daily') }})), toFloat64((select sum(clicks) from {{ ref('fct_linkedin__share_daily') }}))
    union all select 'smm li_organic_follower_gain', toFloat64((select sum(li_organic_follower_gain) from {{ ref('mart_smm__social_daily') }})), toFloat64((select sum(organic_follower_gain) from {{ ref('fct_linkedin__follower_gains_daily') }}))
)
where abs(mart_total - fact_total) > 0.01
