{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='item_daily_key',
    engine='MergeTree()',
    order_by='(tenant_id, date_day, item_daily_key)',
    partition_by='toYYYYMM(date_day)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per tenant, date and item name (ecommerce funnel). -#}

with final as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'date_day', 'item_name']) }} as item_daily_key,
        tenant_id,
        date_day,
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'item_name']) }} as item_key,
        items_viewed, items_added_to_cart, items_purchased, item_revenue,
        cart_to_view_rate, purchase_to_view_rate,
        _loaded_at
    from {{ ref('stg_ga4_lc__ecommerce_items') }}

)

select * from final
{% if is_incremental() %}
where {{ incremental_watermark() }}
{% endif %}
