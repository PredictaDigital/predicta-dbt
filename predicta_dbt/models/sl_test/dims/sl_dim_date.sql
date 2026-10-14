{{ config(
    materialized='table',
    alias='dim_date',
    engine='MergeTree()',
    order_by='date'
) }}

{#- Shared calendar. Timezone convention (set once, here): every `date` in this
    schema is a calendar date in UTC, because the Airbyte sources already report
    whole-day dates (GA4 and Search Console in the property's own day, Lighthouse
    in the fetch day) and are NOT re-timestamped. To move to a tenant-local day,
    change only macros/to_reporting_date.sql, never this table.
    Named sl_dim_date so it does not clash with the existing marts model dim_date;
    the table is created as sl_test.dim_date. -#}

select
    date,
    toYear(date)                      as year,
    toQuarter(date)                   as quarter,
    toMonth(date)                     as month,
    monthName(date)                   as month_name,
    toStartOfMonth(date)              as month_start,
    toISOWeek(date)                   as iso_week,
    toStartOfWeek(date, 1)            as week_start,
    toDayOfWeek(date, 1)              as day_of_week,
    dateName('weekday', date)         as day_name,
    toUInt8(toDayOfWeek(date, 1) >= 6) as is_weekend
from (
    select toDate('2026-01-01') + number as date
    from numbers(dateDiff('day', toDate('2026-01-01'), toDate('2028-12-31')) + 1)
)
