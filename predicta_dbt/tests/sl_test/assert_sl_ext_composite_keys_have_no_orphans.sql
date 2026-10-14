{{ config(tags=['sl_test']) }}
{#- Gate (D5) for the SMM, PPC and extra SEO facts: project-owned dimensions are joined on project_id PLUS the key.
    Returns facts whose connection, page, post, media item or Google Ads campaign is missing from its dimension. Zero rows means no orphans. -#}

    select 'fct_gsc__search_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_gsc__search_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_gsc__search_daily', 'page_key not in dim_page', project_id, toString(page_key) from {{ ref('fct_gsc__search_daily') }} where (project_id, page_key) not in (select project_id, page_key from {{ ref('sl_dim_page') }})
    union all
    select 'fct_gsc__country_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_gsc__country_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_gsc__url_inspection_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_gsc__url_inspection_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_gsc__url_inspection_daily', 'page_key not in dim_page', project_id, toString(page_key) from {{ ref('fct_gsc__url_inspection_daily') }} where (project_id, page_key) not in (select project_id, page_key from {{ ref('sl_dim_page') }})
    union all
    select 'fct_facebook__page_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_facebook__page_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_facebook__page_insights_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_facebook__page_insights_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_facebook__post_insights_snapshot' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_facebook__post_insights_snapshot') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_facebook__post_insights_snapshot', 'post_key not in dim_facebook_post', project_id, toString(post_key) from {{ ref('fct_facebook__post_insights_snapshot') }} where (project_id, post_key) not in (select project_id, post_key from {{ ref('dim_facebook_post') }})
    union all
    select 'fct_instagram__account_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_instagram__account_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_instagram__media_insights_snapshot' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_instagram__media_insights_snapshot') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_instagram__media_insights_snapshot', 'media_key not in dim_instagram_media', project_id, toString(media_key) from {{ ref('fct_instagram__media_insights_snapshot') }} where (project_id, media_key) not in (select project_id, media_key from {{ ref('dim_instagram_media') }})
    union all
    select 'fct_instagram__reach_by_follow_type_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_instagram__reach_by_follow_type_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_instagram__views_by_media_type_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_instagram__views_by_media_type_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_instagram__user_reach_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_instagram__user_reach_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_instagram__profile_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_instagram__profile_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_linkedin__share_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_linkedin__share_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_linkedin__follower_gains_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_linkedin__follower_gains_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_linkedin__follower_count_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_linkedin__follower_count_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__performance_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__performance_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__performance_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__performance_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
    union all
    select 'fct_googleads__ad_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__ad_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__ad_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__ad_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
    union all
    select 'fct_googleads__keyword_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__keyword_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__keyword_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__keyword_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
    union all
    select 'fct_googleads__search_term_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__search_term_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__search_term_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__search_term_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
    union all
    select 'fct_googleads__device_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__device_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__device_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__device_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
    union all
    select 'fct_googleads__age_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__age_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__age_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__age_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
    union all
    select 'fct_googleads__gender_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__gender_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__gender_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__gender_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
    union all
    select 'fct_googleads__location_daily' as fact, 'connection_id not in dim_connection' as problem, project_id, connection_id as key from {{ ref('fct_googleads__location_daily') }} where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
    union all
    select 'fct_googleads__location_daily', 'campaign_id not in dim_googleads_campaign', project_id, toString(campaign_id) from {{ ref('fct_googleads__location_daily') }} where (project_id, toString(campaign_id)) not in (select project_id, toString(campaign_id) from {{ ref('dim_googleads_campaign') }})
