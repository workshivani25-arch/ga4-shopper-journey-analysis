-- 03_cart_abandonment.sql
-- Purpose: measure cart abandonment (sessions that added to cart but did not purchase)
--          and see how far abandoners got, split by device.

WITH sessions AS (
  SELECT
    CONCAT(user_pseudo_id, '-', CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) AS session_key,
    ANY_VALUE(device.category) AS device,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) AS began_checkout,
    MAX(IF(event_name = 'add_shipping_info', 1, 0)) AS added_shipping,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS added_payment,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY session_key
  HAVING session_key IS NOT NULL
)

SELECT
  device,
  COUNTIF(added_to_cart = 1) AS cart_sessions,
  COUNTIF(added_to_cart = 1 AND purchased = 0) AS abandoned_sessions,
  ROUND(SAFE_DIVIDE(COUNTIF(added_to_cart = 1 AND purchased = 0),
                    COUNTIF(added_to_cart = 1)) * 100, 1) AS abandonment_rate_pct,
  -- Where did the abandoners stop? (every column counts abandoned carts only, so they add up)
  COUNTIF(added_to_cart = 1 AND purchased = 0 AND began_checkout = 0) AS left_before_checkout,
  COUNTIF(added_to_cart = 1 AND purchased = 0 AND began_checkout = 1 AND added_payment = 0) AS left_during_checkout,
  COUNTIF(added_to_cart = 1 AND purchased = 0 AND added_payment = 1) AS left_after_entering_payment
FROM sessions
GROUP BY device
ORDER BY cart_sessions DESC;
