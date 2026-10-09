{#- Standard incremental filter: rows loaded since (max _loaded_at - lookback).
    Returns a bare condition so callers can combine it with other predicates.

    alias: pass the source table alias used in the calling model (e.g. 'e') so
    the OUTER column is qualified. The INNER max() always uses the bare column,
    because it reads {{ this }}; qualifying it with the outer alias makes
    ClickHouse treat it as a correlated subquery and reject it.

    ifNull guards the empty-table case, where max() would be NULL and the
    comparison would silently return no rows. -#}
{% macro incremental_watermark(alias=none, column='_loaded_at') -%}
    {{ (alias ~ '.') if alias else '' }}{{ column }} > (
        select ifNull(max({{ column }}), toDateTime(0))
        from {{ this }}
    ) - interval {{ var('incremental_lookback_days') }} day
{%- endmacro %}
