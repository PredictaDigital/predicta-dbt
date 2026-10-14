{{ config(tags=['sl_test']) }}
{#- Gate (D8) for the SMM, PPC and extra SEO facts: every fact measure must equal the deduplicated staging total.
    Pivot facts compare the sum of all their metric columns with the staging value total for the same metrics.
    spend_usd is checked at the AUD test rate of 0.65 (the only currency in the data). Zero rows means all totals agree. -#}

select check_name, fact_total, staging_total
from (
    select 'fct_gsc__search_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_gsc__search_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_gsc__search_all_fields') }})) as staging_total
    union all
    select 'fct_gsc__search_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_gsc__search_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_gsc__search_all_fields') }})) as staging_total
    union all
    select 'fct_gsc__search_daily sum_position' as check_name, toFloat64((select sum(sum_position) from {{ ref('fct_gsc__search_daily') }})) as fact_total, toFloat64((select sum(sum_position) from {{ ref('stg_gsc__search_all_fields') }})) as staging_total
    union all
    select 'fct_gsc__search_daily position_impressions' as check_name, toFloat64((select sum(position_impressions) from {{ ref('fct_gsc__search_daily') }})) as fact_total, toFloat64((select sum(position_impressions) from {{ ref('stg_gsc__search_all_fields') }})) as staging_total
    union all
    select 'fct_gsc__country_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_gsc__country_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_gsc__search_by_country') }})) as staging_total
    union all
    select 'fct_gsc__country_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_gsc__country_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_gsc__search_by_country') }})) as staging_total
    union all
    select 'fct_gsc__country_daily sum_position' as check_name, toFloat64((select sum(sum_position) from {{ ref('fct_gsc__country_daily') }})) as fact_total, toFloat64((select sum(sum_position) from {{ ref('stg_gsc__search_by_country') }})) as staging_total
    union all
    select 'fct_gsc__country_daily position_impressions' as check_name, toFloat64((select sum(position_impressions) from {{ ref('fct_gsc__country_daily') }})) as fact_total, toFloat64((select sum(position_impressions) from {{ ref('stg_gsc__search_by_country') }})) as staging_total
    union all
    select 'fct_gsc__url_inspection_daily inspections' as check_name, toFloat64((select sum(inspections) from {{ ref('fct_gsc__url_inspection_daily') }})) as fact_total, toFloat64((select count() from {{ ref('stg_gsc__url_inspection') }})) as staging_total
    union all
    select 'fct_gsc__url_inspection_daily passed' as check_name, toFloat64((select sum(passed) from {{ ref('fct_gsc__url_inspection_daily') }})) as fact_total, toFloat64((select countIf(verdict = 'PASS') from {{ ref('stg_gsc__url_inspection') }})) as staging_total
    union all
    select 'fct_facebook__page_daily fan_count' as check_name, toFloat64((select sum(fan_count) from {{ ref('fct_facebook__page_daily') }})) as fact_total, toFloat64((select sum(fan_count) from {{ ref('stg_facebook__page') }})) as staging_total
    union all
    select 'fct_facebook__page_daily followers_count' as check_name, toFloat64((select sum(followers_count) from {{ ref('fct_facebook__page_daily') }})) as fact_total, toFloat64((select sum(followers_count) from {{ ref('stg_facebook__page') }})) as staging_total
    union all
    select 'fct_facebook__page_insights_daily metric values' as check_name, toFloat64((select sum(page_media_view) + sum(page_views_total) + sum(page_follows) + sum(page_video_views) + sum(page_video_views_paid) + sum(page_video_views_organic) + sum(page_video_views_unique) + sum(page_video_view_time) + sum(page_video_views_click_to_play) + sum(page_total_actions) + sum(page_post_engagements) + sum(page_daily_follows) + sum(page_daily_follows_unique) + sum(page_daily_unfollows_unique) + sum(page_total_media_view_unique) + sum(page_fan_adds_by_paid_non_paid_unique) + sum(page_lifetime_engaged_followers_unique) from {{ ref('fct_facebook__page_insights_daily') }})) as fact_total, toFloat64((select sum(value) from {{ ref('stg_facebook__page_insights') }} where metric in ('page_media_view', 'page_views_total', 'page_follows', 'page_video_views', 'page_video_views_paid', 'page_video_views_organic', 'page_video_views_unique', 'page_video_view_time', 'page_video_views_click_to_play', 'page_total_actions', 'page_post_engagements', 'page_daily_follows', 'page_daily_follows_unique', 'page_daily_unfollows_unique', 'page_total_media_view_unique', 'page_fan_adds_by_paid_non_paid_unique', 'page_lifetime_engaged_followers_unique'))) as staging_total
    union all
    select 'fct_facebook__post_insights_snapshot metric values' as check_name, toFloat64((select sum(post_media_view) + sum(post_total_media_view_unique) + sum(post_clicks) + sum(post_video_views) + sum(post_video_views_unique) + sum(post_video_complete_views_30s) + sum(post_clicks_by_type) + sum(post_activity_by_action_type) + sum(post_reactions_by_type_total) from {{ ref('fct_facebook__post_insights_snapshot') }})) as fact_total, toFloat64((select sum(value) from {{ ref('stg_facebook__post_insights') }} where metric in ('post_media_view', 'post_total_media_view_unique', 'post_clicks', 'post_video_views', 'post_video_views_unique', 'post_video_complete_views_30s', 'post_clicks_by_type', 'post_activity_by_action_type', 'post_reactions_by_type_total'))) as staging_total
    union all
    select 'fct_instagram__account_daily metric values' as check_name, toFloat64((select sum(reach) + sum(views) + sum(likes) + sum(comments) + sum(saves) + sum(shares) + sum(reposts) + sum(replies) + sum(profile_views) + sum(accounts_engaged) + sum(website_clicks) + sum(profile_links_taps) + sum(total_interactions) from {{ ref('fct_instagram__account_daily') }})) as fact_total, toFloat64((select sum(value) from {{ ref('stg_instagram__account_insights') }} where metric in ('reach', 'views', 'likes', 'comments', 'saves', 'shares', 'reposts', 'replies', 'profile_views', 'accounts_engaged', 'website_clicks', 'profile_links_taps', 'total_interactions'))) as staging_total
    union all
    select 'fct_instagram__media_insights_snapshot metric values' as check_name, toFloat64((select sum(reach) + sum(views) + sum(likes) + sum(comments) + sum(shares) + sum(saved) + sum(follows) + sum(reposts) + sum(profile_activity) + sum(profile_visits) + sum(total_interactions) from {{ ref('fct_instagram__media_insights_snapshot') }})) as fact_total, toFloat64((select sum(value) from {{ ref('stg_instagram__media_insights') }} where metric in ('reach', 'views', 'likes', 'comments', 'shares', 'saved', 'follows', 'reposts', 'profile_activity', 'profile_visits', 'total_interactions'))) as staging_total
    union all
    select 'fct_instagram__reach_by_follow_type_daily reach' as check_name, toFloat64((select sum(reach) from {{ ref('fct_instagram__reach_by_follow_type_daily') }})) as fact_total, toFloat64((select sum(reach) from {{ ref('stg_instagram__reach_by_follow_type') }})) as staging_total
    union all
    select 'fct_instagram__views_by_media_type_daily views' as check_name, toFloat64((select sum(views) from {{ ref('fct_instagram__views_by_media_type_daily') }})) as fact_total, toFloat64((select sum(views) from {{ ref('stg_instagram__views_by_media_type') }})) as staging_total
    union all
    select 'fct_instagram__user_reach_daily reach' as check_name, toFloat64((select sum(reach) from {{ ref('fct_instagram__user_reach_daily') }})) as fact_total, toFloat64((select sum(reach) from {{ ref('stg_instagram__user_reach') }})) as staging_total
    union all
    select 'fct_instagram__user_reach_daily reach_days_28' as check_name, toFloat64((select sum(reach_days_28) from {{ ref('fct_instagram__user_reach_daily') }})) as fact_total, toFloat64((select sum(reach_days_28) from {{ ref('stg_instagram__user_reach') }})) as staging_total
    union all
    select 'fct_instagram__user_reach_daily reach_week' as check_name, toFloat64((select sum(reach_week) from {{ ref('fct_instagram__user_reach_daily') }})) as fact_total, toFloat64((select sum(reach_week) from {{ ref('stg_instagram__user_reach') }})) as staging_total
    union all
    select 'fct_instagram__profile_daily followers_count' as check_name, toFloat64((select sum(followers_count) from {{ ref('fct_instagram__profile_daily') }})) as fact_total, toFloat64((select sum(followers_count) from {{ ref('stg_instagram__profile') }})) as staging_total
    union all
    select 'fct_instagram__profile_daily follows_count' as check_name, toFloat64((select sum(follows_count) from {{ ref('fct_instagram__profile_daily') }})) as fact_total, toFloat64((select sum(follows_count) from {{ ref('stg_instagram__profile') }})) as staging_total
    union all
    select 'fct_instagram__profile_daily media_count' as check_name, toFloat64((select sum(media_count) from {{ ref('fct_instagram__profile_daily') }})) as fact_total, toFloat64((select sum(media_count) from {{ ref('stg_instagram__profile') }})) as staging_total
    union all
    select 'fct_linkedin__share_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_linkedin__share_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_linkedin__share_stats') }})) as staging_total
    union all
    select 'fct_linkedin__share_daily unique_impressions' as check_name, toFloat64((select sum(unique_impressions) from {{ ref('fct_linkedin__share_daily') }})) as fact_total, toFloat64((select sum(unique_impressions) from {{ ref('stg_linkedin__share_stats') }})) as staging_total
    union all
    select 'fct_linkedin__share_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_linkedin__share_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_linkedin__share_stats') }})) as staging_total
    union all
    select 'fct_linkedin__share_daily likes' as check_name, toFloat64((select sum(likes) from {{ ref('fct_linkedin__share_daily') }})) as fact_total, toFloat64((select sum(likes) from {{ ref('stg_linkedin__share_stats') }})) as staging_total
    union all
    select 'fct_linkedin__share_daily comments' as check_name, toFloat64((select sum(comments) from {{ ref('fct_linkedin__share_daily') }})) as fact_total, toFloat64((select sum(comments) from {{ ref('stg_linkedin__share_stats') }})) as staging_total
    union all
    select 'fct_linkedin__share_daily shares' as check_name, toFloat64((select sum(shares) from {{ ref('fct_linkedin__share_daily') }})) as fact_total, toFloat64((select sum(shares) from {{ ref('stg_linkedin__share_stats') }})) as staging_total
    union all
    select 'fct_linkedin__follower_gains_daily organic_follower_gain' as check_name, toFloat64((select sum(organic_follower_gain) from {{ ref('fct_linkedin__follower_gains_daily') }})) as fact_total, toFloat64((select sum(organic_follower_gain) from {{ ref('stg_linkedin__follower_gains') }})) as staging_total
    union all
    select 'fct_linkedin__follower_gains_daily paid_follower_gain' as check_name, toFloat64((select sum(paid_follower_gain) from {{ ref('fct_linkedin__follower_gains_daily') }})) as fact_total, toFloat64((select sum(paid_follower_gain) from {{ ref('stg_linkedin__follower_gains') }})) as staging_total
    union all
    select 'fct_linkedin__follower_count_daily first_degree_size' as check_name, toFloat64((select sum(first_degree_size) from {{ ref('fct_linkedin__follower_count_daily') }})) as fact_total, toFloat64((select sum(first_degree_size) from {{ ref('stg_linkedin__follower_count') }})) as staging_total
    union all
    select 'fct_googleads__performance_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__performance_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__performance') }})) as staging_total
    union all
    select 'fct_googleads__performance_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__performance_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__performance') }})) as staging_total
    union all
    select 'fct_googleads__performance_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__performance_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__performance') }})) as staging_total
    union all
    select 'fct_googleads__performance_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__performance_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__performance') }})) as staging_total
    union all
    select 'fct_googleads__performance_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__performance_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__performance') }})) as staging_total
    union all
    select 'fct_googleads__performance_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__performance_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__performance') }})) as staging_total
    union all
    select 'fct_googleads__performance_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__performance_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__performance') }})) as staging_total
    union all
    select 'fct_googleads__ad_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__ad_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__ad_performance') }})) as staging_total
    union all
    select 'fct_googleads__ad_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__ad_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__ad_performance') }})) as staging_total
    union all
    select 'fct_googleads__ad_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__ad_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__ad_performance') }})) as staging_total
    union all
    select 'fct_googleads__ad_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__ad_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__ad_performance') }})) as staging_total
    union all
    select 'fct_googleads__ad_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__ad_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__ad_performance') }})) as staging_total
    union all
    select 'fct_googleads__ad_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__ad_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__ad_performance') }})) as staging_total
    union all
    select 'fct_googleads__ad_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__ad_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__ad_performance') }})) as staging_total
    union all
    select 'fct_googleads__keyword_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__keyword_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__keyword_performance') }})) as staging_total
    union all
    select 'fct_googleads__keyword_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__keyword_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__keyword_performance') }})) as staging_total
    union all
    select 'fct_googleads__keyword_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__keyword_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__keyword_performance') }})) as staging_total
    union all
    select 'fct_googleads__keyword_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__keyword_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__keyword_performance') }})) as staging_total
    union all
    select 'fct_googleads__keyword_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__keyword_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__keyword_performance') }})) as staging_total
    union all
    select 'fct_googleads__keyword_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__keyword_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__keyword_performance') }})) as staging_total
    union all
    select 'fct_googleads__keyword_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__keyword_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__keyword_performance') }})) as staging_total
    union all
    select 'fct_googleads__search_term_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__search_term_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__search_term_performance') }})) as staging_total
    union all
    select 'fct_googleads__search_term_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__search_term_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__search_term_performance') }})) as staging_total
    union all
    select 'fct_googleads__search_term_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__search_term_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__search_term_performance') }})) as staging_total
    union all
    select 'fct_googleads__search_term_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__search_term_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__search_term_performance') }})) as staging_total
    union all
    select 'fct_googleads__search_term_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__search_term_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__search_term_performance') }})) as staging_total
    union all
    select 'fct_googleads__search_term_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__search_term_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__search_term_performance') }})) as staging_total
    union all
    select 'fct_googleads__search_term_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__search_term_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__search_term_performance') }})) as staging_total
    union all
    select 'fct_googleads__device_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__device_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__device_performance') }})) as staging_total
    union all
    select 'fct_googleads__device_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__device_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__device_performance') }})) as staging_total
    union all
    select 'fct_googleads__device_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__device_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__device_performance') }})) as staging_total
    union all
    select 'fct_googleads__device_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__device_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__device_performance') }})) as staging_total
    union all
    select 'fct_googleads__device_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__device_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__device_performance') }})) as staging_total
    union all
    select 'fct_googleads__device_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__device_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__device_performance') }})) as staging_total
    union all
    select 'fct_googleads__device_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__device_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__device_performance') }})) as staging_total
    union all
    select 'fct_googleads__age_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__age_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__age_performance') }})) as staging_total
    union all
    select 'fct_googleads__age_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__age_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__age_performance') }})) as staging_total
    union all
    select 'fct_googleads__age_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__age_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__age_performance') }})) as staging_total
    union all
    select 'fct_googleads__age_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__age_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__age_performance') }})) as staging_total
    union all
    select 'fct_googleads__age_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__age_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__age_performance') }})) as staging_total
    union all
    select 'fct_googleads__age_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__age_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__age_performance') }})) as staging_total
    union all
    select 'fct_googleads__age_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__age_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__age_performance') }})) as staging_total
    union all
    select 'fct_googleads__gender_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__gender_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__gender_performance') }})) as staging_total
    union all
    select 'fct_googleads__gender_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__gender_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__gender_performance') }})) as staging_total
    union all
    select 'fct_googleads__gender_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__gender_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__gender_performance') }})) as staging_total
    union all
    select 'fct_googleads__gender_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__gender_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__gender_performance') }})) as staging_total
    union all
    select 'fct_googleads__gender_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__gender_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__gender_performance') }})) as staging_total
    union all
    select 'fct_googleads__gender_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__gender_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__gender_performance') }})) as staging_total
    union all
    select 'fct_googleads__gender_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__gender_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__gender_performance') }})) as staging_total
    union all
    select 'fct_googleads__location_daily impressions' as check_name, toFloat64((select sum(impressions) from {{ ref('fct_googleads__location_daily') }})) as fact_total, toFloat64((select sum(impressions) from {{ ref('stg_googleads__location_performance') }})) as staging_total
    union all
    select 'fct_googleads__location_daily clicks' as check_name, toFloat64((select sum(clicks) from {{ ref('fct_googleads__location_daily') }})) as fact_total, toFloat64((select sum(clicks) from {{ ref('stg_googleads__location_performance') }})) as staging_total
    union all
    select 'fct_googleads__location_daily cost_micros' as check_name, toFloat64((select sum(cost_micros) from {{ ref('fct_googleads__location_daily') }})) as fact_total, toFloat64((select sum(cost_micros) from {{ ref('stg_googleads__location_performance') }})) as staging_total
    union all
    select 'fct_googleads__location_daily conversions' as check_name, toFloat64((select sum(conversions) from {{ ref('fct_googleads__location_daily') }})) as fact_total, toFloat64((select sum(conversions) from {{ ref('stg_googleads__location_performance') }})) as staging_total
    union all
    select 'fct_googleads__location_daily conversions_value' as check_name, toFloat64((select sum(conversions_value) from {{ ref('fct_googleads__location_daily') }})) as fact_total, toFloat64((select sum(conversions_value) from {{ ref('stg_googleads__location_performance') }})) as staging_total
    union all
    select 'fct_googleads__location_daily spend' as check_name, toFloat64((select sum(spend) from {{ ref('fct_googleads__location_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 from {{ ref('stg_googleads__location_performance') }})) as staging_total
    union all
    select 'fct_googleads__location_daily spend_usd' as check_name, toFloat64((select sum(spend_usd) from {{ ref('fct_googleads__location_daily') }})) as fact_total, toFloat64((select sum(cost_micros) / 1000000 * 0.65 from {{ ref('stg_googleads__location_performance') }})) as staging_total
)
where abs(fact_total - staging_total) > 0.001
