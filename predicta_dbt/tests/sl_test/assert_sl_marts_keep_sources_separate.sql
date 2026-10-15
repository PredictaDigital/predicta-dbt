{{ config(tags=['sl_test']) }}
{#- Gates D11 and D12.
    D11: every measure column of the digital marketing mart carries a source qualifier (ga4_, gsc_, ppc_ or
    platform_), so measures from different sources can never be mistaken for one another.
    D12: every measure column of the three marts is listed in the metric catalogue, and a measure that is not
    comparable across sources is never named with a bare generic word such as sessions or clicks.
    Returns one row per violation; zero rows means all rules hold. -#}

{%- set marts = ['mart_seo__search_daily', 'mart_ppc__campaign_daily', 'mart_dm__channel_daily'] -%}
{%- set not_measures = ['campaign_key', 'page_key', 'search_daily_key', 'campaign_daily_key', 'channel_daily_key'] -%}
{%- set generic = ['sessions', 'clicks', 'impressions', 'conversions', 'users', 'views', 'spend'] -%}

{% set measure_rows = [] %}
{% for m in marts %}
  {% for col in adapter.get_columns_in_relation(ref(m)) %}
    {% if col.is_number() and col.name not in not_measures %}
      {% do measure_rows.append((m, col.name)) %}
    {% endif %}
  {% endfor %}
{% endfor %}

select problem, mart, column_name
from (
    {% for m, c in measure_rows %}
    select 'measure column not in metric catalogue' as problem, '{{ m }}' as mart, '{{ c }}' as column_name
    where ('{{ m }}', '{{ c }}') not in (select mart, column_name from {{ ref('metric_catalog') }})
    union all
    {% if m == 'mart_dm__channel_daily' %}
    select 'digital marketing measure without a source qualifier', '{{ m }}', '{{ c }}'
    where not (startsWith('{{ c }}', 'ga4_') or startsWith('{{ c }}', 'gsc_') or startsWith('{{ c }}', 'ppc_') or startsWith('{{ c }}', 'platform_'))
    union all
    {% endif %}
    {% endfor %}
    select 'non-comparable measure named with a generic word' as problem, mart, column_name
    from {{ ref('metric_catalog') }}
    where comparable = 'false' and metric in ({% for g in generic %}'{{ g }}'{{ ', ' if not loop.last }}{% endfor %})
)
