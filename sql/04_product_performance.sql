-- 04_product_performance.sql
-- Purpose: find products that attract lots of views but rarely sell ("browsed, not bought")
--          versus products that convert consistently. Useful for merchandising and placement.

WITH item_events AS (
  SELECT
    event_name,
    item.item_name AS item_name,
    item.item_category AS item_category,
    IFNULL(item.quantity, 1) AS quantity,
    IFNULL(item.item_revenue, 0) AS item_revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
    UNNEST(items) AS item
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart', 'purchase')
    AND item.item_name IS NOT NULL
    AND item.item_name != '(not set)'
),

products AS (
  SELECT
    item_name,
    ANY_VALUE(item_category) AS item_category,
    COUNTIF(event_name = 'view_item') AS views,
    COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
    SUM(IF(event_name = 'purchase', quantity, 0)) AS units_sold,
    ROUND(SUM(IF(event_name = 'purchase', item_revenue, 0)), 2) AS revenue
  FROM item_events
  GROUP BY item_name
  HAVING views >= 200  -- enough views for a reliable rate
),

scored AS (
  SELECT
    *,
    ROUND(SAFE_DIVIDE(add_to_carts, views) * 100, 1) AS view_to_cart_pct,
    ROUND(SAFE_DIVIDE(units_sold, views) * 100, 2) AS units_per_100_views
  FROM products
)

SELECT
  *,
  CASE
    WHEN views >= (SELECT APPROX_QUANTILES(views, 4)[OFFSET(3)] FROM scored)
         AND units_per_100_views <= (SELECT APPROX_QUANTILES(units_per_100_views, 4)[OFFSET(1)] FROM scored)
      THEN 'High interest, low conversion'
    WHEN units_per_100_views >= (SELECT APPROX_QUANTILES(units_per_100_views, 4)[OFFSET(3)] FROM scored)
      THEN 'Strong converter'
    ELSE 'Middle of the pack'
  END AS product_group
FROM scored
ORDER BY views DESC;
