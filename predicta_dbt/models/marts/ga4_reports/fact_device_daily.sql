{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='device_daily_key',
    engine='MergeTree()',
    order_by='(tenant_id, date_day, device_daily_key)',
    partition_by='toYYYYMM(date_day)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per tenant, date, device category, OS and browser.
    OS and browser stay as degenerate columns; device_key links to dim_device. -#}

with final as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'date_day', 'device_category', 'operating_system', 'browser']) }} as device_daily_key,
        tenant_id,
        date_day,
        {{ dbt_utils.generate_surrogate_key(
            ["coalesce(nullIf(device_category, ''), 'unknown')"]) }} as device_key,
        operating_system,
        browser,
        total_users, new_users, sessions, sessions_per_user, avg_session_duration_sec,
        pageviews, pageviews_per_session, bounce_rate,
        _loaded_at
    from {{ ref('stg_ga4_lc__devices') }}

)

select * from final
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
