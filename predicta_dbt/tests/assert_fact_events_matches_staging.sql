{#- Gate: after a build, fact_events must hold every staged event exactly once. -#}
select
    (select count() from {{ ref('stg_ga4__events') }}) as stg_events,
    (select count() from {{ ref('fact_events') }})     as fact_events
where stg_events != fact_events
