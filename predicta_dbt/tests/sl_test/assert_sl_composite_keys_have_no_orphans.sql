{{ config(tags=['sl_test']) }}
{#- Gate (D5): project-owned dimensions are joined on project_id PLUS the key, never
    on the key alone. Returns facts whose (project_id, page_key) is missing from
    dim_page, or whose (project_id, connection_id) is missing from dim_connection.
    Zero rows means no orphans. -#}

with page_refs as (
    select 'fct_ga4__page_daily' as fact, project_id, page_key from {{ ref('fct_ga4__page_daily') }}
    union all select 'fct_gsc__page_daily', project_id, page_key from {{ ref('fct_gsc__page_daily') }}
    union all select 'fct_lighthouse__report_daily', project_id, page_key from {{ ref('fct_lighthouse__report_daily') }}
    union all select 'fct_lighthouse__audit_daily', project_id, page_key from {{ ref('fct_lighthouse__audit_daily') }}
),

connection_refs as (
    select 'fct_ga4__traffic_daily' as fact, project_id, connection_id from {{ ref('fct_ga4__traffic_daily') }}
    union all select 'fct_ga4__page_daily', project_id, connection_id from {{ ref('fct_ga4__page_daily') }}
    union all select 'fct_gsc__site_daily', project_id, connection_id from {{ ref('fct_gsc__site_daily') }}
    union all select 'fct_gsc__page_daily', project_id, connection_id from {{ ref('fct_gsc__page_daily') }}
    union all select 'fct_gsc__device_daily', project_id, connection_id from {{ ref('fct_gsc__device_daily') }}
    union all select 'fct_gsc__query_daily', project_id, connection_id from {{ ref('fct_gsc__query_daily') }}
    union all select 'fct_lighthouse__report_daily', project_id, connection_id from {{ ref('fct_lighthouse__report_daily') }}
    union all select 'fct_lighthouse__audit_daily', project_id, connection_id from {{ ref('fct_lighthouse__audit_daily') }}
)

select distinct fact, 'page_key not in dim_page' as problem, toString(project_id) as project_id, toString(page_key) as key
from page_refs
where (project_id, page_key) not in (select project_id, page_key from {{ ref('sl_dim_page') }})

union all

select distinct fact, 'connection_id not in dim_connection', toString(project_id), toString(connection_id)
from connection_refs
where (project_id, connection_id) not in (select project_id, connection_id from {{ ref('dim_connection') }})
