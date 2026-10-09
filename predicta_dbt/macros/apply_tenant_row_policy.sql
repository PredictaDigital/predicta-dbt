{#- Second isolation layer (ClickHouse row policy). DISABLED by default.

    Why disabled: Cube connects as ONE ClickHouse user, so a policy keyed on
    the user does not separate tenants. A working design needs a per-query
    setting that Cube sets from the JWT claim (the SQL_ custom-setting prefix
    pattern) or per-tenant ClickHouse users. Decide that first, then enable
    with --vars '{apply_row_policies: true}'.

    Also verify: after a `table` rebuild (dbt swaps the table), confirm the
    policy still exists on the new table. tests/ should assert it. -#}
{% macro apply_tenant_row_policy(users='cube_user') -%}
    {%- if var('apply_row_policies', false) -%}
        create row policy if not exists tenant_guard on {{ this }}
        for select using tenant_id = getSetting('SQL_tenant_id') to {{ users }}
    {%- else -%}
        select 1
    {%- endif -%}
{%- endmacro %}
