-- 05_rfm_segments.sql
-- Purpose: segment purchasing customers by Recency, Frequency and Monetary value (RFM),
--          then profile how each segment browses the site.
-- Recency is measured from the last day of the dataset (2021-01-31).

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

customers AS (
  SELECT
    user_pseudo_id,
    DATE_DIFF(DATE '2021-01-31', MAX(event_date), DAY) AS recency_days,
    COUNT(DISTINCT transaction_id) AS frequency,
    ROUND(SUM(purchase_revenue), 2) AS monetary
  FROM events
  WHERE event_name = 'purchase'
    AND transaction_id IS NOT NULL
    AND transaction_id != '(not set)'
  GROUP BY user_pseudo_id
  HAVING monetary > 0
),

browsing AS (
  SELECT
    user_pseudo_id,
    COUNT(DISTINCT ga_session_id) AS sessions,
    COUNTIF(event_name = 'view_item') AS items_viewed,
    COUNTIF(event_name = 'add_to_cart') AS add_to_carts
  FROM events
  GROUP BY user_pseudo_id
),

scored AS (
  SELECT
    c.*,
    b.sessions,
    b.items_viewed,
    b.add_to_carts,
    NTILE(3) OVER (ORDER BY c.recency_days DESC) AS r_score,  -- 3 = bought most recently
    NTILE(3) OVER (ORDER BY c.monetary) AS m_score             -- 3 = spent the most
  FROM customers c
  JOIN browsing b USING (user_pseudo_id)
),

segmented AS (
  SELECT
    *,
    CASE
      WHEN frequency >= 2 AND m_score = 3 THEN 'Champions'
      WHEN frequency >= 2 THEN 'Loyal repeat buyers'
      WHEN r_score = 3 AND m_score = 3 THEN 'Recent big spenders'
      WHEN r_score = 3 THEN 'New one-time buyers'
      WHEN r_score = 1 THEN 'At risk (lapsed)'
      ELSE 'Occasional buyers'
    END AS segment
  FROM scored
)

SELECT
  segment,
  COUNT(*) AS customers,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS pct_of_customers,
  ROUND(SUM(monetary) / SUM(SUM(monetary)) OVER () * 100, 1) AS pct_of_revenue,
  ROUND(AVG(monetary), 2) AS avg_spend,
  ROUND(AVG(recency_days), 1) AS avg_days_since_purchase,
  ROUND(AVG(sessions), 1) AS avg_sessions,
  ROUND(AVG(items_viewed), 1) AS avg_items_viewed,
  ROUND(AVG(add_to_carts), 1) AS avg_add_to_carts
FROM segmented
GROUP BY segment
ORDER BY pct_of_revenue DESC;
