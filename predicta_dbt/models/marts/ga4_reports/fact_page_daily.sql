{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='page_daily_key',
    engine='MergeTree()',
    order_by='(tenant_id, date_day, page_daily_key)',
    partition_by='toYYYYMM(date_day)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per tenant, date and page path. The report has one row per
    host and path+query string, so rows are rolled up to path (same key as
    dim_page). Bounce rate is not additive: it is re-weighted by page views. -#}

with aggregated as (

    select
        tenant_id,
        date_day,
        page_path,
        sum(pageviews)                  as total_pageviews,
        sum(bounce_rate * pageviews)    as bounce_weighted,
        max(_loaded_at)                 as _loaded_at
    from {{ ref('stg_ga4_lc__pages') }}
    group by tenant_id, date_day, page_path

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'date_day', 'page_path']) }} as page_daily_key,
        tenant_id,
        date_day,
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'page_path']) }} as page_key,
        total_pageviews                                  as pageviews,
        bounce_weighted / nullIf(total_pageviews, 0)     as bounce_rate,
        _loaded_at
    from aggregated

)

select * from final
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
