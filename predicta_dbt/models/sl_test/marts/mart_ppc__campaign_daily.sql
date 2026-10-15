{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='campaign_daily_key',
    engine='MergeTree()',
    order_by='(project_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Domain mart for paid advertising. Grain: project, connection, date, campaign.
    Built by UNION ALL of the ad platform facts at one shared grain (campaign and day).
    Google Ads is the only platform with performance data loaded so far; Meta Ads and
    LinkedIn Ads join the union when their performance streams are available.
    Conversions are platform-reported and therefore kept under the name platform_conversions.
    Whole campaign-days are re-aggregated whenever any of their rows is new. -#}

with src as (

    select
        customer_id, project_id, source_app_id, connection_id, source_account_id,
        date, campaign_id, impressions, clicks,
        spend      as spend_original,
        currency,
        spend_usd,
        conversions as platform_conversions,
        _loaded_at
    from {{ ref('fct_googleads__performance_daily') }}

),

touched as (

    select distinct project_id, connection_id, date, campaign_id
    from src
    {% if is_incremental() %}
    where {{ incremental_watermark() }}
    {% endif %}

)

select
    {{ dbt_utils.generate_surrogate_key(['s.project_id', 's.connection_id', 's.date', 's.campaign_id']) }} as campaign_daily_key,
    toLowCardinality(any(s.customer_id))        as customer_id,
    toLowCardinality(s.project_id)              as project_id,
    toLowCardinality(any(s.source_app_id))      as source_app_id,
    toLowCardinality(s.connection_id)           as connection_id,
    toLowCardinality(any(s.source_account_id))  as source_account_id,
    s.date                                      as date,
    sipHash64(s.project_id, s.connection_id, s.campaign_id) as campaign_key,
    toLowCardinality(s.campaign_id)             as campaign_id,
    sum(s.impressions)                          as impressions,
    sum(s.clicks)                               as clicks,
    sum(s.spend_original)                       as spend_original,
    toLowCardinality(any(s.currency))           as currency,
    sum(s.spend_usd)                            as spend_usd,
    sum(s.platform_conversions)                 as platform_conversions,
    max(s._loaded_at)                           as _loaded_at
from src as s
where (s.project_id, s.connection_id, s.date, s.campaign_id) in (select project_id, connection_id, date, campaign_id from touched)
group by s.project_id, s.connection_id, s.date, s.campaign_id
