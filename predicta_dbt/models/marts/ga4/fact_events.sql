{{ config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='event_key',
    engine='MergeTree()',
    order_by='(tenant_id, event_date, event_key)',
    partition_by='toYYYYMM(event_date)',
    post_hook="{{ apply_tenant_row_policy() }}"
) }}

{#- Grain: one row per GA4 event.
    Incremental with a lookback window so late or reprocessed events are
    picked up. delete_insert removes any existing row with the same event_key
    before inserting, so reruns never duplicate. -#}

select
    e.tenant_id                                                        as tenant_id,
    e.event_key                                                        as event_key,
    e.session_key                                                      as session_key,
    {{ to_reporting_date('e.event_ts') }}                              as event_date,
    e.event_ts                                                         as event_ts,
    e.event_name                                                       as event_name,

    -- dimension keys (same hash recipe as the dimensions)
    {{ dbt_utils.generate_surrogate_key(
        ['e.tenant_id', 'path(e.page_location)']) }}                   as page_key,
    {{ dbt_utils.generate_surrogate_key(
        ["coalesce(nullIf(e.device_category, ''), 'unknown')"]) }}     as device_key,
    {{ dbt_utils.generate_surrogate_key(
        ["coalesce(nullIf(m.channel_group, ''), 'Unassigned')"]) }}                as channel_key,

    -- degenerate dimensions kept on the fact (wide facts are cheap in ClickHouse)
    e.source                                                           as source,
    e.medium                                                           as medium,
    e.campaign                                                         as campaign,

    -- measures
    e.engagement_time_msec                                             as engagement_time_msec,
    toUInt8(1)                                                         as event_count,

    e._loaded_at                                                       as _loaded_at

from {{ ref('stg_ga4__events') }} as e
left join {{ ref('channel_mapping') }} as m
    on e.source = m.source and e.medium = m.medium

{% if is_incremental() %}
where {{ incremental_watermark('e') }}
{% endif %}
