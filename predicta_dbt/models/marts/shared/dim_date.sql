{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='date_day'
) }}

{#- Global calendar. No tenant_id: it is reference data, identical for everyone.
    date_day is a pure calendar date; the timezone decision is applied when
    facts derive their date (see macros/to_reporting_date.sql), not here. -#}

select
    date_day,
    toYear(date_day)                      as year,
    toQuarter(date_day)                   as quarter,
    toMonth(date_day)                     as month,
    monthName(date_day)                   as month_name,
    toStartOfMonth(date_day)              as month_start,
    toISOWeek(date_day)                   as iso_week,
    toStartOfWeek(date_day, 1)            as week_start,   -- Monday
    toDayOfWeek(date_day, 1)              as day_of_week,  -- 1 = Monday
    dateName('weekday', date_day)         as day_name,
    toDayOfWeek(date_day, 1) >= 6         as is_weekend
from (
    select
        toDate('{{ var("date_spine_start") }}') + number as date_day
    from numbers(
        dateDiff('day',
                 toDate('{{ var("date_spine_start") }}'),
                 toDate('{{ var("date_spine_end") }}')) + 1)
)
