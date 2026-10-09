{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='site_daily_key',
    engine='MergeTree()',
    order_by='(tenant_id, date_day)',
    partition_by='toYYYYMM(date_day)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per tenant and date. Site totals joined with daily active
    users. Each source contributes zeros for the measures it does not carry, so
    summing per key combines them without a nullable full join. Ratios are not
    additive, but each key has exactly one source row per measure, so sum()
    returns that single value. -#}

with combined as (

    select
        tenant_id, date_day,
        total_users, new_users, sessions, sessions_per_user, avg_session_duration_sec,
        pageviews, pageviews_per_session, bounce_rate,
        toInt64(0) as active_users_1d,
        _loaded_at
    from {{ ref('stg_ga4_lc__website_overview') }}

    union all

    select
        tenant_id, date_day,
        toInt64(0), toInt64(0), toInt64(0), toFloat64(0), toFloat64(0),
        toInt64(0), toFloat64(0), toFloat64(0),
        active_users_1d,
        _loaded_at
    from {{ ref('stg_ga4_lc__daily_active_users') }}

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'date_day']) }} as site_daily_key,
        tenant_id                            as tenant_id,
        date_day                             as date_day,
        sum(total_users)                     as total_users,
        sum(new_users)                       as new_users,
        sum(sessions)                        as sessions,
        sum(sessions_per_user)               as sessions_per_user,
        sum(avg_session_duration_sec)        as avg_session_duration_sec,
        sum(pageviews)                       as pageviews,
        sum(pageviews_per_session)           as pageviews_per_session,
        sum(bounce_rate)                     as bounce_rate,
        sum(active_users_1d)                 as active_users_1d,
        max(_loaded_at)                      as _loaded_at
    from combined
    group by tenant_id, date_day

)

select * from final
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
