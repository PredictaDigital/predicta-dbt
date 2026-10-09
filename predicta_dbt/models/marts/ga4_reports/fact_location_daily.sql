{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='location_daily_key',
    engine='MergeTree()',
    order_by='(tenant_id, date_day, location_daily_key)',
    partition_by='toYYYYMM(date_day)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per tenant, date, country, region and city. -#}

with final as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'date_day', 'country', 'region', 'city']) }} as location_daily_key,
        tenant_id,
        date_day,
        {{ dbt_utils.generate_surrogate_key(['country', 'region', 'city']) }} as location_key,
        total_users, new_users, sessions, sessions_per_user, avg_session_duration_sec,
        pageviews, pageviews_per_session, bounce_rate,
        _loaded_at
    from {{ ref('stg_ga4_lc__locations') }}

)

select * from final
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
