{{ config(
    materialized='table',
    engine='MergeTree()',
    order_by='channel_key'
) }}

{#- Global marketing-channel dimension built from the seed. 'Unassigned' always
    exists so a fact row can never be orphaned by an unmapped source/medium. -#}

select
    {{ dbt_utils.generate_surrogate_key(['channel_group']) }} as channel_key,
    channel_group
from (
    select distinct channel_group from {{ ref('channel_mapping') }}
    union distinct
    select 'Unassigned' as channel_group
)
