-- ============================================================================
-- CredResolve Collections Analytics — GOLDEN DATASET BUILD
-- ============================================================================
-- Purpose: Transform 17 raw source tables into a trustworthy analytical layer.
-- Every cleaning decision below is documented with WHY, not just WHAT.
--
-- GLOBAL ENTITY-RESOLUTION RULE (applies to the whole file):
--   `borrower_id` inside every event/fact table (calls, call_attempts,
--   call_dispositions, whatsapp_events, sms_events, field_visits,
--   promises_to_pay, payments, complaints, account_status_history) does NOT
--   match the authoritative borrower_id in `accounts` (verified match rate:
--   0.0%, i.e. statistical noise). It is DROPPED from every golden table.
--   The only trustworthy identity keys are: account_id (fact-table grain)
--   and agent_id (agent grain). Borrower attributes must always be fetched
--   via account_id -> accounts.borrower_id -> borrowers.*, never directly.
--
--   Similarly, `agents.csv` is NOT a usable dimension table: each agent_id
--   has ~30 rows, each carrying a DIFFERENT agent_name/employee_code/team
--   (verified: a name maps to ~949 of 1000 possible agent_ids on average —
--   effectively random). We keep agent_id as an anonymous performance
--   bucket only; agent_name/employee_code/team/status from agents.csv are
--   quarantined (not loaded into golden_agents beyond the bare key).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. GOLDEN_PAYMENTS
-- ----------------------------------------------------------------------------
-- Issue found: 500 payment_id are EXACT full-row duplicates (re-ingestion
--   glitch — same payment_id, same everything, copy-pasted). These inflate
--   recovery ~2% if left in. FIX: drop via SELECT DISTINCT on payment_id.
-- Issue found (TRAP — do NOT "fix" this the obvious way): payment_reference
--   (the TXN code) is reused across 3,746 groups of totally UNRELATED
--   payments — different account_id, different amount, different month,
--   sometimes different payment_status, spanning up to 200+ days apart.
--   This is a reference-collision bug in the source system, not duplicate
--   ingestion. If you naively "dedupe by payment_reference" you silently
--   DELETE real, distinct payments belonging to different customers —
--   this alone would fabricate a ~25% fake decline in recovery if applied
--   (verified by comparing both dedup strategies). We do NOT dedupe on
--   payment_reference. It is kept as a raw attribute only, flagged unreliable.
-- Missing data: 382 rows have a NULL payment_reference — kept (payment_id
--   is still a valid unique key), flagged.
DROP TABLE IF EXISTS golden_payments;
CREATE TABLE golden_payments AS
WITH deduped AS (
    SELECT DISTINCT ON (payment_id) *
    FROM payments
    ORDER BY payment_id, (payment_reference IS NOT NULL) DESC  -- prefer the copy that has a reference, if versions differ
)
SELECT
    payment_id,
    account_id,
    -- borrower_id intentionally dropped (unreliable, see header)
    event_at,
    payment_reference,
    (payment_reference IS NULL) AS ref_missing_flag,
    amount,
    payment_status,
    payment_method,
    provider_id
FROM deduped;

-- ----------------------------------------------------------------------------
-- 2. GOLDEN_CALLS
-- ----------------------------------------------------------------------------
-- Issue found: 1,350 exact-duplicate call_id rows (re-ingestion). Dropped.
-- Issue found: calls.timezone does not correspond reliably to the account's
--   own timezone (verified: for the same account_id, calls appear tagged
--   with all 3 possible timezone values in ~38% of accounts — i.e. the tz
--   label looks close to randomly assigned per event, not a true property
--   of the call). Raw hour-of-day distribution is also almost perfectly
--   flat across all 24 hours (3,683–3,949 calls/hour) which is not
--   realistic for a real call center. CONCLUSION: the timezone field
--   cannot be used to determine true local calling hour. We keep the raw
--   UTC-naive event_at and the raw timezone label as-is for audit, but flag
--   calling-time analysis as UNRELIABLE and exclude it from confident
--   conclusions (documented in Data Quality Report, not silently dropped).
DROP TABLE IF EXISTS golden_calls;
CREATE TABLE golden_calls AS
WITH deduped AS (
    SELECT DISTINCT ON (call_id) *
    FROM calls
    ORDER BY call_id, event_at
)
SELECT
    call_id, account_id, event_at, agent_id, campaign_id, direction,
    vendor_id, call_status, duration_sec,
    timezone AS reported_timezone,
    TRUE AS timezone_unreliable_flag
FROM deduped;

-- ----------------------------------------------------------------------------
-- 3. GOLDEN_CALL_ATTEMPTS / GOLDEN_CALL_DISPOSITIONS
-- ----------------------------------------------------------------------------
-- call_attempts: no exact PK duplicates found. Pass through (drop borrower_id).
DROP TABLE IF EXISTS golden_call_attempts;
CREATE TABLE golden_call_attempts AS
SELECT attempt_id, account_id, event_at, call_id, agent_id, attempt_no,
       vendor_id, attempt_status
FROM call_attempts;

-- call_dispositions: no exact PK duplicates. BUT disposition_code changed
--   across schema versions (legacy/v1/v2): legacy contains BOTH
--   'PROMISE_TO_PAY' and 'PTP' as separate codes (~1,332 and ~1,296 rows
--   respectively) referring to the same real-world event; v1/v2 use only
--   'PTP'. We map both to one canonical code so trend counting isn't split.
DROP TABLE IF EXISTS golden_call_dispositions;
CREATE TABLE golden_call_dispositions AS
SELECT
    disposition_id, account_id, event_at, call_id, agent_id,
    disposition_code AS raw_disposition_code,
    CASE WHEN disposition_code IN ('PROMISE_TO_PAY','PTP') THEN 'PTP'
         ELSE disposition_code END AS canonical_disposition_code,
    disposition_version
FROM call_dispositions;

-- ----------------------------------------------------------------------------
-- 4. GOLDEN_WHATSAPP_EVENTS / GOLDEN_SMS_EVENTS
-- ----------------------------------------------------------------------------
-- whatsapp_events: 600 exact-duplicate whatsapp_event_id rows. Dropped.
-- sms_events: no exact PK duplicates found.
DROP TABLE IF EXISTS golden_whatsapp_events;
CREATE TABLE golden_whatsapp_events AS
SELECT DISTINCT ON (whatsapp_event_id) whatsapp_event_id, account_id, event_at,
       message_id, event_type, template_code, provider_id
FROM whatsapp_events
ORDER BY whatsapp_event_id, event_at;

DROP TABLE IF EXISTS golden_sms_events;
CREATE TABLE golden_sms_events AS
SELECT sms_event_id, account_id, event_at, message_id, event_type,
       template_code, provider_id
FROM sms_events;

-- ----------------------------------------------------------------------------
-- 5. GOLDEN_FIELD_VISITS / GOLDEN_PROMISES_TO_PAY / GOLDEN_COMPLAINTS
-- ----------------------------------------------------------------------------
-- No exact PK duplicates found in any of these three. Pass through, borrower_id dropped.
DROP TABLE IF EXISTS golden_field_visits;
CREATE TABLE golden_field_visits AS
SELECT visit_id, account_id, event_at, agent_id, visit_type, outcome,
       latitude, longitude, scheduled_at
FROM field_visits;

DROP TABLE IF EXISTS golden_promises_to_pay;
CREATE TABLE golden_promises_to_pay AS
SELECT ptp_id, account_id, event_at, agent_id, promised_amount,
       promised_date, status, source
FROM promises_to_pay;

DROP TABLE IF EXISTS golden_complaints;
CREATE TABLE golden_complaints AS
SELECT complaint_id, account_id, event_at, complaint_type, severity,
       status, source, resolution_at
FROM complaints;

-- ----------------------------------------------------------------------------
-- 6. GOLDEN_ACCOUNT_STATUS_HISTORY
-- ----------------------------------------------------------------------------
-- No exact PK duplicates. "Same account+status appearing 4-5 times" turned
--   out to be GENUINE repeated status transitions over time (different
--   event_at each time, e.g. an account legitimately cycling through
--   DELINQUENT -> ACTIVE -> DELINQUENT), not literal duplicate rows — kept.
-- event_at (when status truly changed) vs recorded_at (when the system
--   logged it) diverge in ~50% of rows — genuine late-arriving /
--   backdated events. We keep BOTH columns: event_at is the business-truth
--   timestamp used for all "what happened when" analysis; recorded_at is
--   preserved for point-in-time / as-of-date reproducibility in production
--   (see Part 5 — late-arriving data handling).
DROP TABLE IF EXISTS golden_account_status_history;
CREATE TABLE golden_account_status_history AS
SELECT history_id, account_id, event_at, status, changed_by, source, recorded_at
FROM account_status_history;

-- ----------------------------------------------------------------------------
-- 7. GOLDEN_AGENT_SESSIONS / GOLDEN_DAILY_TARGETING / GOLDEN_CAMPAIGNS
-- ----------------------------------------------------------------------------
-- No exact PK duplicates in any of these three. Pass through.
DROP TABLE IF EXISTS golden_agent_sessions;
CREATE TABLE golden_agent_sessions AS SELECT * FROM agent_sessions;

DROP TABLE IF EXISTS golden_campaigns;
CREATE TABLE golden_campaigns AS SELECT * FROM campaigns;

-- daily_targeting: verified this is NOT a full census of the addressable
--   portfolio — most accounts appear in it for only 1-2 months out of 7-8
--   (11,203 of ~23k accounts appear in exactly 1 month), and only ~17% of
--   successful payments can even be matched to a daily_targeting record in
--   the prior 30 days. FLAG: do not use daily_targeting as "the denominator"
--   for portfolio-wide contact/conversion rates — it under-represents the
--   true active population. Use `accounts` (filtered to non-terminal status)
--   as the denominator instead; use daily_targeting only for campaign-level
--   analysis where its own coverage is the acknowledged scope.
DROP TABLE IF EXISTS golden_daily_targeting;
CREATE TABLE golden_daily_targeting AS SELECT * FROM daily_targeting;

-- ----------------------------------------------------------------------------
-- 8. GOLDEN_ACCOUNTS / GOLDEN_BORROWERS / GOLDEN_AGENTS (dim) / GOLDEN_VENDOR_TELEPHONY
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS golden_accounts;
CREATE TABLE golden_accounts AS SELECT * FROM accounts;  -- clean: 30,000 rows, account_id unique, verified 1:1 to borrower_id

DROP TABLE IF EXISTS golden_borrowers;
CREATE TABLE golden_borrowers AS SELECT * FROM borrowers;

-- golden_agents: agent_id is the ONLY trustworthy field from agents.csv.
--   All other columns (name/employee_code/team/status) are quarantined —
--   see header note. We surface just the key so fact tables can join to it,
--   plus a data-quality flag so downstream users know not to trust a join
--   to agent attributes.
DROP TABLE IF EXISTS golden_agents;
CREATE TABLE golden_agents AS
SELECT DISTINCT agent_id, TRUE AS identity_attributes_unreliable_flag
FROM agents;

DROP TABLE IF EXISTS golden_vendor_telephony;
CREATE TABLE golden_vendor_telephony AS SELECT * FROM vendor_telephony;
