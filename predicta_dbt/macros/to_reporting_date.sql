{#- The ONE place the reporting timezone is applied.
    Today: var('reporting_timezone') for every tenant (UTC by default).
    Tenant-local later: join dim_tenant.timezone and replace the literal below,
    here and only here. -#}
{% macro to_reporting_date(ts_col) -%}
    toDate(toTimeZone({{ ts_col }}, '{{ var("reporting_timezone") }}'))
{%- endmacro %}
