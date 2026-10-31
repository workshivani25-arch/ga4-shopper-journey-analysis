-- 01_data_quality.sql
-- Purpose: check the GA4 event data is trustworthy before analysing it.
-- Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce (Google Merchandise Store, Nov 2020 - Jan 2021)
-- Output: one row per check, with the number and share of affected events.

WITH events AS (
  SELECT
    event_name,
    event_timestamp,
    user_pseudo_id,
    traffic_source.source AS source,
    traffic_source.medium AS medium,
    ecommerce.transaction_id AS transaction_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

totals AS (
  SELECT COUNT(*) AS total_events FROM events
),

duplicates AS (
  -- Same user, same event, same microsecond: almost certainly a double-fired tag.
  SELECT IFNULL(SUM(cnt - 1), 0) AS duplicate_events  -- 0 when no duplicates exist
  FROM (
    SELECT user_pseudo_id, event_name, event_timestamp, COUNT(*) AS cnt
    FROM events
    GROUP BY 1, 2, 3
    HAVING COUNT(*) > 1
  )
),

checks AS (
  SELECT 'Events missing ga_session_id' AS check_name,
         COUNTIF(ga_session_id IS NULL) AS affected_events
  FROM events
  UNION ALL
  -- Obfuscated or missing source: genuinely unusable for channel analysis.
  SELECT 'Events with obfuscated or missing traffic source',
         COUNTIF(source IS NULL OR medium IS NULL
                 OR source = '(data deleted)' OR medium = '(data deleted)')
  FROM events
  UNION ALL
  -- Direct traffic is a valid channel, reported separately for context, not as an error.
  SELECT 'Events from direct traffic (valid, for context)',
         COUNTIF(source = '(direct)' AND medium = '(none)')
  FROM events
  UNION ALL
  SELECT 'Purchase events missing transaction_id',
         COUNTIF(event_name = 'purchase'
                 AND (transaction_id IS NULL OR transaction_id = '(not set)'))
  FROM events
  UNION ALL
  SELECT 'Duplicate events (same user, event and timestamp)',
         (SELECT duplicate_events FROM duplicates)
)

SELECT
  c.check_name,
  c.affected_events,
  t.total_events,
  ROUND(SAFE_DIVIDE(c.affected_events, t.total_events) * 100, 2) AS pct_of_all_events
FROM checks c
CROSS JOIN totals t
ORDER BY c.affected_events DESC;
