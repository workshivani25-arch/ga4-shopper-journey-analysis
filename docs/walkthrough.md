# Project walkthrough (plain English)

Use this to understand every part of the project, so you can explain it confidently in an interview.

## How GA4 data is structured

GA4 records **events**, not page hits. Every action (viewing a product, adding to cart, purchasing) is a row in the export with:

- `user_pseudo_id`: an anonymous ID for the browser/device
- `event_name`: what happened (`view_item`, `add_to_cart`, `begin_checkout`, `purchase`...)
- `event_params`: a nested list of extra details. The session ID (`ga_session_id`) and session number (`ga_session_number`) live here, so we pull them out with `UNNEST`.
- `items`: a nested list of products involved in the event
- `device`, `traffic_source`, `ecommerce`: grouped fields (records)

There is one table per day (`events_20201101`, ...). `events_*` with `_TABLE_SUFFIX` queries a date range across them.

**Interview line:** "In GA4 a session isn't its own table. I rebuilt sessions by combining `user_pseudo_id` with `ga_session_id` from the event parameters."

## 01 – Data quality

Before trusting results, I checked four things:
- **Missing session IDs** → those events can't be assigned to a session, so they're excluded from the funnel.
- **Duplicate events** (same user, event and microsecond) → usually a tag firing twice; inflates counts.
- **Unassigned/obfuscated traffic** → if a large share is unknown, channel comparisons are only indicative.
- **Purchases without a transaction ID** → can't be de-duplicated, so they may overstate orders.

This links directly to "tracking, tag management and data quality" in a Digital Analyst role.

## 02 – Funnel by segment

For each session I flag whether it ever reached each step (`MAX(IF(event_name = ..., 1, 0))`). Then I count sessions per step and calculate **step-to-step** conversion (e.g. of sessions that added to cart, what % began checkout). Step-to-step rates show *where* people leave, which an overall conversion rate hides.

New vs returning uses `ga_session_number`: if a user's session number is 1, it's their first visit.

## 03 – Cart abandonment

Abandonment = sessions that added to cart but didn't purchase. I also split abandoners by the last checkout step they reached (cart, shipping, payment). Leaving at the cart suggests price/shipping-cost shock or browsing; leaving at payment suggests friction or trust issues.

## 04 – Product performance

`UNNEST(items)` turns each product in an event into its own row. For each product: views, add-to-carts, units sold, and units sold per 100 views. Products in the top quarter for views but bottom quarter for conversion are flagged **"high interest, low conversion"**: people want them, but something (price, images, sizing, stock) stops the sale.

## 05 – RFM segments

- **Recency:** days since last purchase
- **Frequency:** number of orders
- **Monetary:** total spend

Customers get scores with `NTILE(3)` (splits them into thirds) and are labelled (Champions, At risk, etc.). Comparing % of customers with % of revenue shows how concentrated value is, and the browsing columns show whether valuable customers behave differently.

## Likely interview questions

- *What was the biggest finding?* → your largest funnel drop-off and what you'd do about it.
- *How did you know the data was reliable?* → the data quality checks and what they showed.
- *What would you do with David Jones' data?* → connect online behaviour to store and stock data (e.g. click-and-collect, out-of-stock items with high views).
- *Limitations?* → sample data, one store, three months, session-level funnel not strict order.
