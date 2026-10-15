{#- Date of a snapshot row: the stream's own synced_date when it has one, otherwise the UTC
    day the row was extracted (older syncs of some streams carry no synced_date). -#}
{% macro sl_snapshot_date(synced_date_expr, extracted_at_expr) -%}
    if({{ synced_date_expr }} != '', toDate({{ synced_date_expr }}), toDate(fromUnixTimestamp64Milli(toInt64({{ extracted_at_expr }}), 'UTC')))
{%- endmacro %}
