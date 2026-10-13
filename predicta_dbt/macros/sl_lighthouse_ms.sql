{#- Lighthouse reports timings as display strings with a unit ("2.6 s", "0 ms"),
    sometimes separated by a non-breaking space. JSONExtractFloat would turn those
    into 0 without any error, so parse them explicitly and return milliseconds.
    A plain JSON number is passed through unchanged (assumed to be milliseconds). -#}
{% macro sl_lighthouse_ms(json_col, key) -%}
    if(JSONType({{ json_col }}, '{{ key }}') = 'String',
       multiIf(
           match(JSONExtractString({{ json_col }}, '{{ key }}'), 'ms$'),
               toFloat64OrZero(replaceAll(extract(JSONExtractString({{ json_col }}, '{{ key }}'), '([0-9][0-9,.]*)'), ',', '')),
           match(JSONExtractString({{ json_col }}, '{{ key }}'), 's$'),
               toFloat64OrZero(replaceAll(extract(JSONExtractString({{ json_col }}, '{{ key }}'), '([0-9][0-9,.]*)'), ',', '')) * 1000,
           toFloat64OrZero(replaceAll(extract(JSONExtractString({{ json_col }}, '{{ key }}'), '([0-9][0-9,.]*)'), ',', ''))),
       JSONExtractFloat({{ json_col }}, '{{ key }}'))
{%- endmacro %}
