{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='(project_id)'
) }}

select toLowCardinality(project_id) as project_id, toLowCardinality(connection_id) as connection_id, toLowCardinality(source_app_id) as platform, account_id, customer_name as account_name, currency, '' as status
from {{ ref('stg_googleads__customer') }}
union all
select toLowCardinality(project_id), toLowCardinality(connection_id), toLowCardinality(source_app_id), account_id, account_name, currency, status
from {{ ref('stg_linkedinads__accounts') }}
union all
select toLowCardinality(project_id), toLowCardinality(connection_id), toLowCardinality(source_app_id), source_account_id as account_id,
       argMax(account_name, _extracted_at) as account_name, argMaxIf(currency, _extracted_at, currency != '') as currency, '' as status
from {{ ref('stg_metaads__ad_account') }}
group by project_id, connection_id, source_app_id, source_account_id
