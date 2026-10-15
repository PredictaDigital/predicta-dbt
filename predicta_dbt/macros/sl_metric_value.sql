{#- Read a numeric value from a JSON fragment that may be a number, a quoted number or an
    object. Objects are summed over their members, except when they carry a 'total' key
    (Facebook paid/unpaid splits), which is used as is so the parts are not double counted.
    Pass a SQL expression that yields the raw JSON text, e.g. JSONExtractRaw(d, 'value'). -#}
{% macro sl_metric_value(raw) -%}
    multiIf(
        JSONType({{ raw }}) IN ('Int64', 'UInt64', 'Double', 'Bool'), JSONExtractFloat({{ raw }}),
        JSONType({{ raw }}) = 'Object' AND JSONHas({{ raw }}, 'total'), JSONExtractFloat({{ raw }}, 'total'),
        JSONType({{ raw }}) = 'Object', arraySum(arrayMap(kv -> toFloat64OrZero(kv.2), JSONExtractKeysAndValuesRaw({{ raw }}))),
        toFloat64OrZero(trim(BOTH '"' FROM {{ raw }})))
{%- endmacro %}
