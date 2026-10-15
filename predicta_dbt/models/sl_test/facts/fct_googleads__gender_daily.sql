{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='gender_daily_key',
    engine='MergeTree()',
    order_by='(project_id, connection_id, date)',
    partition_by='toYYYYMM(date)'
) }}

{#- Google Ads performance per day and audience gender. Spend is converted to USD at the fixed test rate in the sl_currency_rates seed. -#}

select
    {{ dbt_utils.generate_surrogate_key(['s.project_id', 's.connection_id', 's.date', 's.campaign_id', 's.ad_group_id', 's.gender']) }} as gender_daily_key,
    toLowCardinality(s.customer_id)        as customer_id,
    toLowCardinality(s.project_id)         as project_id,
    toLowCardinality(s.source_app_id)      as source_app_id,
    toLowCardinality(s.connection_id)      as connection_id,
    toLowCardinality(s.source_account_id)  as source_account_id,
    s.date as date,
    toLowCardinality(s.campaign_id) as campaign_id,
    toLowCardinality(s.ad_group_id) as ad_group_id,
    toLowCardinality(s.gender) as gender,
    toLowCardinality(s.currency) as currency,
    s.impressions,
    s.clicks,
    s.cost_micros,
    s.conversions,
    s.conversions_value,
    s.cost_micros / 1000000 as spend,
    round(s.cost_micros / 1000000 * ifNull(r.usd_rate, 0), 6) as spend_usd,
    s._loaded_at as _loaded_at
from {{ ref('stg_googleads__gender_performance') }} as s
left join {{ ref('sl_currency_rates') }} as r on s.currency = r.currency
{% if is_incremental() %}
where {{ incremental_watermark('s') }}
{% endif %}
