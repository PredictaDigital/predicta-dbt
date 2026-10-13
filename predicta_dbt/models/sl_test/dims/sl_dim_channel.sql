{{ config(
    materialized='table',
    alias='dim_channel',
    engine='MergeTree()',
    order_by='(source, medium)'
) }}

{#- Shared reference: one row per source and medium. The channel group comes from
    the channel_map seed. A combination GA4 reports that the seed does not list is
    still included (never dropped): referral medium falls back to 'Referral',
    anything else to 'Unassigned'. Named sl_dim_channel so it does not clash with
    the existing marts model; the table is created as sl_test.dim_channel. -#}

with mapped as (

    select source, medium, channel_group from {{ ref('channel_map') }}

),

observed as (

    select distinct source, medium
    from {{ ref('stg_ga4__traffic_sources') }}

),

unlisted as (

    select
        o.source as source,
        o.medium as medium,
        if(o.medium = 'referral', 'Referral', 'Unassigned') as channel_group
    from observed as o
    where (o.source, o.medium) not in (select source, medium from mapped)

),

combined as (

    select source, medium, channel_group from mapped
    union all
    select source, medium, channel_group from unlisted

)

select
    sipHash64(source, medium)  as channel_key,
    source,
    medium,
    channel_group
from combined
