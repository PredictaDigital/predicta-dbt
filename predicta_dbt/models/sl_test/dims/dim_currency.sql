{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='currency'
) }}

select currency, usd_rate, note
from {{ ref('sl_currency_rates') }}
