{#- Some streams carry no account id (for example Instagram media, Google Ads performance). When
    a source app has exactly one connection, such rows belong to it. Returns that connection's
    source_account_id; use it as the fallback in coalesce(nullif(<id>, ''), ...). -#}
{% macro sl_sole_account(app) -%}
    (select any(source_account_id) from {{ ref('sl_connections') }} where source_app_id = '{{ app }}')
{%- endmacro %}
