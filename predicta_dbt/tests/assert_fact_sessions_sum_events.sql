{#- Gate: events counted across sessions must equal events in fact_events. -#}
select
    (select sum(events) from {{ ref('fact_sessions') }}) as session_events,
    (select count()     from {{ ref('fact_events') }})   as fact_events
where session_events != fact_events
