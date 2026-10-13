{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='audit_id'
) }}

{#- Shared reference: one row per Lighthouse audit id with its current title and
    description (latest extract wins). The audit catalogue is the same for every
    project. -#}

select
    audit_id,
    argMax(audit_title, _extracted_at)          as audit_title,
    argMax(audit_description, _extracted_at)    as audit_description
from {{ ref('stg_lighthouse__audit') }}
group by audit_id
