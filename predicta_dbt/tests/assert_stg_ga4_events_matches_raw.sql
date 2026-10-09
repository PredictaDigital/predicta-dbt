{#- Gate: staging row count per tenant must equal the number of DISTINCT events
    in raw. Any difference means rows were dropped or invented unexplained.
    Returns the offending tenants; the test passes when zero rows come back.
    Keep the key columns in step with stg_ga4__events. -#}

with raw_counts as (
    select tenant_id, uniqExact(user_pseudo_id, ga_session_id, event_name,
                                toDateTime64(event_timestamp, 3, 'UTC')) as raw_events
    from {{ source('raw', 'raw_ga4_events') }}
    group by tenant_id
),
stg_counts as (
    select tenant_id, count() as stg_events
    from {{ ref('stg_ga4__events') }}
    group by tenant_id
)
select
    coalesce(nullIf(r.tenant_id, ''), s.tenant_id) as tenant_id,
    r.raw_events,
    s.stg_events
from raw_counts r
full outer join stg_counts s on r.tenant_id = s.tenant_id
where ifNull(r.raw_events, 0) != ifNull(s.stg_events, 0)
