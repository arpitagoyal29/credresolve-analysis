-- ============================================================================
-- CredResolve Collections Analytics — DATA FORENSICS QUERIES
-- ============================================================================
-- One query per forensic question in the assignment brief (Part 2, A-G).
-- Run against the RAW tables (pre-golden) so the "before" state is visible.
-- Results referenced in DATA_QUALITY_REPORT.md.
-- ============================================================================

-- A. Duplicate payments -------------------------------------------------------
-- A1. True exact-duplicate payment_id rows
SELECT count(*) AS n_dupe_payment_ids, sum(c-1) AS extra_rows
FROM (SELECT payment_id, count(*) c FROM payments GROUP BY 1 HAVING count(*)>1) d;

-- A2. Reference-collision trap: same TXN reference on unrelated payments
WITH dupe_refs AS (
  SELECT payment_reference FROM payments
  WHERE payment_reference IS NOT NULL GROUP BY 1 HAVING count(*)>1
)
SELECT p.payment_reference, count(*) n_rows,
       count(DISTINCT p.account_id) distinct_accounts,
       count(DISTINCT p.amount) distinct_amounts,
       date_diff('day', min(p.event_at), max(p.event_at)) AS day_span
FROM payments p JOIN dupe_refs d ON p.payment_reference = d.payment_reference
GROUP BY 1 ORDER BY n_rows DESC LIMIT 20;

-- B. Attribution errors -------------------------------------------------------
-- What % of successful payments can be matched to ANY campaign touch (30-day window)?
WITH matched AS (
  SELECT DISTINCT p.payment_id
  FROM payments p JOIN daily_targeting dt ON p.account_id = dt.account_id
  WHERE p.payment_status='SUCCESS'
    AND p.event_at BETWEEN dt.target_date AND dt.target_date + INTERVAL 30 DAY
)
SELECT
  (SELECT count(*) FROM payments WHERE payment_status='SUCCESS') AS total_success,
  (SELECT count(*) FROM matched) AS matched_to_campaign,
  round(100.0 * (SELECT count(*) FROM matched) /
        (SELECT count(*) FROM payments WHERE payment_status='SUCCESS'), 1) AS pct_attributable;

-- C. Timezone problems --------------------------------------------------------
-- How many distinct timezone labels appear for calls on the SAME account?
WITH t AS (SELECT account_id, count(DISTINCT timezone) tzc FROM calls GROUP BY 1)
SELECT tzc AS distinct_tz_labels_seen, count(*) AS n_accounts FROM t GROUP BY 1 ORDER BY 1;

-- Raw hour-of-day distribution (flatness check — real call centers are NOT flat)
SELECT extract(hour FROM event_at) AS hr, count(*) n FROM calls GROUP BY 1 ORDER BY 1;

-- D. Vendor / disposition code changes ----------------------------------------
SELECT disposition_version, disposition_code, count(*) n
FROM call_dispositions GROUP BY 1,2 ORDER BY 1,3 DESC;

-- E. Agent identity problems --------------------------------------------------
-- E1. Rows per agent_id, and how many DIFFERENT names/employee_codes appear under it
WITH d AS (SELECT agent_id, count(*) c, count(DISTINCT agent_name) names,
                  count(DISTINCT employee_code) codes FROM agents GROUP BY 1)
SELECT min(c) min_rows, max(c) max_rows, avg(c) avg_rows,
       avg(names) avg_distinct_names_per_id, avg(codes) avg_distinct_codes_per_id
FROM d;

-- E2. borrower_id integrity check — match rate vs accounts master, per fact table
-- (repeat this block per table: calls, call_attempts, call_dispositions,
--  whatsapp_events, sms_events, field_visits, promises_to_pay, payments,
--  complaints, account_status_history)
SELECT count(*) AS total,
       count(*) FILTER (WHERE t.borrower_id = a.borrower_id) AS matches,
       round(100.0*count(*) FILTER (WHERE t.borrower_id = a.borrower_id)/count(*), 1) AS pct_match
FROM payments t JOIN accounts a ON t.account_id = a.account_id;

-- F. Portfolio mix changes ----------------------------------------------------
SELECT date_trunc('month', c.event_at) mo, a.risk_segment, count(*) n_calls,
       round(avg(a.dpd),1) avg_dpd
FROM calls c JOIN accounts a ON c.account_id = a.account_id
GROUP BY 1,2 ORDER BY 1,2;

-- D2. (completed on recheck) Are calls still routed through vendors marked INACTIVE?
SELECT v.status AS vendor_status, count(*) n_calls
FROM calls c JOIN vendor_telephony v ON c.vendor_id = v.vendor_id
GROUP BY 1;
-- Finding: 60% of calls (54,089/90,000) route through INACTIVE-labeled vendors,
-- continuously through the full window including the final days of data.
-- vendor_telephony.status does not reflect true operational history.

-- Geography driver (via the trustworthy account_id path, NOT event-table borrower_id)
SELECT b.state, count(DISTINCT p.account_id) accts_paid, sum(p.amount) recovered
FROM payments p
JOIN accounts a ON p.account_id = a.account_id
JOIN borrowers b ON a.borrower_id = b.borrower_id
WHERE p.payment_status = 'SUCCESS'
GROUP BY 1 ORDER BY 3 DESC;

-- Attempt-frequency driver
SELECT attempt_no, count(*) n,
       round(100.0*avg(CASE WHEN EXISTS(
           SELECT 1 FROM payments p WHERE p.account_id=ca.account_id AND p.payment_status='SUCCESS'
           AND p.event_at BETWEEN ca.event_at AND ca.event_at + INTERVAL 30 DAY
       ) THEN 1 ELSE 0 END), 2) AS pct_later_paid
FROM call_attempts ca WHERE attempt_no <= 7 GROUP BY 1 ORDER BY 1;

-- G. Denominator manipulation --------------------------------------------------
-- G1. Does the daily_targeting status mix shift over time?
SELECT date_trunc('month', target_date) mo, status, count(*) n,
       round(100.0*count(*)/sum(count(*)) OVER (PARTITION BY date_trunc('month', target_date)), 1) pct
FROM daily_targeting GROUP BY 1,2 ORDER BY 1,2;

-- G2. How many months does each account actually appear in daily_targeting? (coverage check)
WITH am AS (
  SELECT account_id, count(DISTINCT date_trunc('month', target_date)) n_months
  FROM daily_targeting GROUP BY 1
)
SELECT n_months, count(*) n_accounts FROM am GROUP BY 1 ORDER BY 1;
