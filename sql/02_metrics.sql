-- ============================================================================
-- CredResolve Collections Analytics — INDEPENDENT METRIC DEFINITIONS
-- ============================================================================
-- For each metric we (a) state our definition, (b) state why we redefined it
-- if we did, and (c) compute it monthly from the GOLDEN tables only.
--
-- CONTACT RATE
--   Def: ANSWERED calls / total calls (golden_calls.call_status='ANSWERED')
--   Note: this is really "someone picked up," not proof it was the right
--   person. We do NOT call this RPC (see below) because the data cannot
--   support that stronger claim.
--
-- RPC (Right-Party Contact) — REDEFINED / DOWNGRADED
--   The dataset has no field confirming the person who answered was the
--   actual borrower. We therefore do not report a true RPC number — doing
--   so would overstate what we know. We report Contact Rate instead and
--   flag RPC as "not measurable from available data" in the report.
--
-- PTP RATE
--   Def: promises_to_pay created / calls with a logged disposition that
--   month (uses call_dispositions as the "meaningful contact" denominator,
--   since disposition coverage (28,971 calls) is a more honest proxy for
--   "an actual conversation happened" than raw ANSWERED status, which we
--   found is inconsistently populated relative to dispositions).
--
-- PTP KEPT RATE
--   Def: KEPT / (KEPT + BROKEN), excluding OPEN (still pending, not yet
--   resolved) and CANCELLED (withdrawn, not a completion outcome). Mixing
--   OPEN into the denominator would understate kept-rate for the most
--   recent month simply because those PTPs haven't come due yet — a
--   textbook attribution-window bias.
--
-- RECOVERY RATE
--   Def: SUCCESS payment amount (golden_payments) / total outstanding_amount
--   of accounts NOT YET closed/paid at that point. Approximated using
--   current accounts.outstanding_amount as we do not have a time-varying
--   balance table.
--
-- RECOVERY PER ACCOUNT (WORKED)
--   Def: SUCCESS amount / distinct accounts touched that month (touched =
--   appears in calls, whatsapp, sms, or field_visits that month). This is
--   NOT the same as daily_targeting-based attribution, which we found
--   covers only ~17% of successful payments — using it as a denominator
--   would badly understate the true worked population.
--
-- RECOVERY PER AGENT-HOUR
--   Def: total SUCCESS amount / total agent-hours logged (golden_agent_sessions,
--   logout_at - login_at). Portfolio-level — does not require per-payment
--   campaign attribution, so it avoids the 17%-coverage problem entirely.
--
-- COST PER RUPEE RECOVERED
--   No real cost table exists in this dataset. We compute this ONLY under
--   explicitly stated assumed unit costs (see notebook/memo), never as a
--   bare "fact."
--
-- CHANNEL CONVERSION
--   Def: SUCCESS payments / touches, by campaign channel, using only the
--   ~17% of payments that CAN be matched to a daily_targeting record within
--   30 days. Reported with an explicit low-confidence flag — this is a
--   correlation on a small, non-random subset, not a portfolio-wide fact.
-- ============================================================================

DROP TABLE IF EXISTS monthly_metrics;
CREATE TABLE monthly_metrics AS
WITH months AS (
    SELECT DISTINCT date_trunc('month', event_at) AS mo FROM golden_calls
),
calls_agg AS (
    SELECT date_trunc('month', event_at) mo,
           count(*) AS total_calls,
           count(*) FILTER (WHERE call_status='ANSWERED') AS answered_calls
    FROM golden_calls GROUP BY 1
),
disp_agg AS (
    SELECT date_trunc('month', event_at) mo, count(*) AS dispositions
    FROM golden_call_dispositions GROUP BY 1
),
ptp_agg AS (
    SELECT date_trunc('month', event_at) mo,
           count(*) AS ptps_created,
           sum(promised_amount) AS ptp_amount_promised
    FROM golden_promises_to_pay GROUP BY 1
),
ptp_kept AS (
    SELECT date_trunc('month', event_at) mo,
           count(*) FILTER (WHERE status='KEPT') AS kept,
           count(*) FILTER (WHERE status='BROKEN') AS broken
    FROM golden_promises_to_pay GROUP BY 1
),
pay_agg AS (
    SELECT date_trunc('month', event_at) mo,
           sum(amount) FILTER (WHERE payment_status='SUCCESS') AS recovered_gross,
           sum(amount) FILTER (WHERE payment_status='REVERSED') AS reversed_amt,
           count(*) FILTER (WHERE payment_status='SUCCESS') AS n_success
    FROM golden_payments GROUP BY 1
),
touched AS (
    SELECT mo, count(DISTINCT account_id) AS accounts_touched FROM (
        SELECT date_trunc('month', event_at) mo, account_id FROM golden_calls
        UNION ALL SELECT date_trunc('month', event_at), account_id FROM golden_whatsapp_events
        UNION ALL SELECT date_trunc('month', event_at), account_id FROM golden_sms_events
        UNION ALL SELECT date_trunc('month', event_at), account_id FROM golden_field_visits
    ) x GROUP BY 1
),
agent_hours AS (
    SELECT date_trunc('month', login_at) mo,
           sum(date_diff('minute', login_at, logout_at))/60.0 AS agent_hours
    FROM golden_agent_sessions WHERE logout_at IS NOT NULL GROUP BY 1
)
SELECT
    m.mo,
    c.total_calls, c.answered_calls,
    round(100.0*c.answered_calls/nullif(c.total_calls,0),2) AS contact_rate_pct,
    d.dispositions,
    p.ptps_created,
    round(100.0*p.ptps_created/nullif(d.dispositions,0),2) AS ptp_rate_pct,
    pk.kept, pk.broken,
    round(100.0*pk.kept/nullif(pk.kept+pk.broken,0),2) AS ptp_kept_rate_pct,
    pay.recovered_gross,
    pay.reversed_amt,
    round(pay.recovered_gross - coalesce(pay.reversed_amt,0),2) AS recovered_net,
    pay.n_success,
    t.accounts_touched,
    round(pay.recovered_gross/nullif(t.accounts_touched,0),2) AS recovery_per_account,
    ah.agent_hours,
    round(pay.recovered_gross/nullif(ah.agent_hours,0),2) AS recovery_per_agent_hour
FROM months m
LEFT JOIN calls_agg c ON m.mo=c.mo
LEFT JOIN disp_agg d ON m.mo=d.mo
LEFT JOIN ptp_agg p ON m.mo=p.mo
LEFT JOIN ptp_kept pk ON m.mo=pk.mo
LEFT JOIN pay_agg pay ON m.mo=pay.mo
LEFT JOIN touched t ON m.mo=t.mo
LEFT JOIN agent_hours ah ON m.mo=ah.mo
ORDER BY m.mo;
