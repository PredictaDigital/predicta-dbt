-- SYNTHETIC sample data for local testing only. Includes duplicates, empty
-- sources, an unmapped source/medium and null engagement on purpose.
INSERT INTO raw.tenants (tenant_id, tenant_name, timezone, plan) VALUES
  ('t_acme','Acme Pty','Australia/Sydney','pro'),
  ('t_beta','Beta Co','UTC','standard');

INSERT INTO raw.raw_ga4_events (tenant_id, event_timestamp, event_name, user_pseudo_id, ga_session_id, page_location, device_category, traffic_source, traffic_medium, traffic_campaign, engagement_time_msec, _loaded_at)
SELECT
  tenant_id,
  toDateTime64(toStartOfDay(now() - toIntervalDay(s % 10)) + toIntervalSecond((s * 137) % 80000 + e * 20), 6, 'UTC'),
  multiIf(e = 3 AND s % 7 = 0, 'purchase', e = 2, 'scroll', 'page_view'),
  concat('u', toString(s % 80)),
  toInt64(1000 + s),
  concat('https://example.com/', arrayElement(['', 'pricing', 'blog/a', 'contact'], 1 + (s + e) % 4), '?utm=x'),
  arrayElement(['desktop','mobile','tablet',''], 1 + s % 4),
  arrayElement(['google','google','Facebook','','newsletter','Bing'], 1 + s % 6),
  arrayElement(['organic','cpc','social','','email_blast','Organic'], 1 + s % 6),
  arrayElement(['','spring','','','blast1',''], 1 + s % 6),
  if(s % 11 = 0, NULL, toUInt32((s * e * 1300) % 15000 + 100)),
  now64(3)
FROM (SELECT arrayJoin(['t_acme','t_beta']) AS tenant_id) AS t
CROSS JOIN (SELECT number AS s FROM numbers(300)) AS sa
CROSS JOIN (SELECT number AS e FROM numbers(4)) AS ea
WHERE e < 2 + s % 3;

-- Re-landed duplicates for one tenant (later _loaded_at)
INSERT INTO raw.raw_ga4_events
SELECT tenant_id, event_timestamp, event_name, user_pseudo_id, ga_session_id, page_location, device_category, traffic_source, traffic_medium, traffic_campaign, engagement_time_msec, now64(3), 'relanded'
FROM raw.raw_ga4_events WHERE tenant_id = 't_acme' AND ga_session_id % 10 = 0;
