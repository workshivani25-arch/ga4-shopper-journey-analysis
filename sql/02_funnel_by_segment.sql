-- 02_funnel_by_segment.sql
-- Purpose: build the purchase funnel (view item -> add to cart -> checkout -> purchase)
--          at session level, split by device, traffic medium and new vs returning users.
-- A session "reaches" a step if it fired that event at least once.

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    device.category AS device,
    traffic_source.medium AS medium,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number') AS ga_session_number
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

sessions AS (
  SELECT
    CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) AS session_key,
    ANY_VALUE(device) AS device,
    -- Group the many medium values into a handful of readable channels
    CASE
      WHEN ANY_VALUE(medium) = 'organic' THEN 'Organic search'
      WHEN ANY_VALUE(medium) IN ('cpc', 'ppc', 'paid') THEN 'Paid search'
      WHEN ANY_VALUE(medium) = 'referral' THEN 'Referral'
      WHEN ANY_VALUE(medium) = '(none)' THEN 'Direct'
      WHEN ANY_VALUE(medium) = '(data deleted)' THEN 'Unknown (obfuscated)'
      ELSE 'Other'
    END AS channel,
    IF(MIN(ga_session_number) = 1, 'New', 'Returning') AS customer_type,
    MAX(IF(event_name = 'view_item', 1, 0)) AS viewed_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) AS began_checkout,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased
  FROM events
  WHERE ga_session_id IS NOT NULL
  GROUP BY session_key
),

by_segment AS (
  SELECT 'Device' AS segment_type, device AS segment, * EXCEPT (session_key, device, channel, customer_type)
  FROM sessions
  UNION ALL
  SELECT 'Channel', channel, * EXCEPT (session_key, device, channel, customer_type)
  FROM sessions
  UNION ALL
  SELECT 'Customer type', customer_type, * EXCEPT (session_key, device, channel, customer_type)
  FROM sessions
  UNION ALL
  SELECT 'All', 'All sessions', * EXCEPT (session_key, device, channel, customer_type)
  FROM sessions
)

SELECT
  segment_type,
  segment,
  COUNT(*) AS sessions,
  SUM(viewed_item) AS view_item_sessions,
  SUM(added_to_cart) AS add_to_cart_sessions,
  SUM(began_checkout) AS checkout_sessions,
  SUM(purchased) AS purchase_sessions,
  -- Step-to-step conversion: where in the funnel do people leave?
  ROUND(SAFE_DIVIDE(SUM(added_to_cart), SUM(viewed_item)) * 100, 1) AS view_to_cart_pct,
  ROUND(SAFE_DIVIDE(SUM(began_checkout), SUM(added_to_cart)) * 100, 1) AS cart_to_checkout_pct,
  ROUND(SAFE_DIVIDE(SUM(purchased), SUM(began_checkout)) * 100, 1) AS checkout_to_purchase_pct,
  ROUND(SAFE_DIVIDE(SUM(purchased), COUNT(*)) * 100, 2) AS session_conversion_pct
FROM by_segment
GROUP BY segment_type, segment
HAVING COUNT(*) >= 500  -- ignore tiny segments with unreliable rates
ORDER BY segment_type, sessions DESC;
