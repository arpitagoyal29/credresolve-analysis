-- ============================================================================
-- PART 4 — COUNTERFACTUAL: "What if we hadn't changed targeting strategy?"
-- ============================================================================
-- METHODOLOGY: Difference-in-Differences (DiD)
--
-- Treatment group   : accounts targeted by campaigns using the NEWER
--                      targeting-strategy generation (strategy_version IN ('v2','v3'))
-- Control group     : accounts targeted by campaigns using the OLDER
--                      generation (strategy_version IN ('legacy','v1'))
-- Time split        : campaigns.start_at < median(start_at) = "EARLY" cohort,
--                      else "LATE" cohort. (No single clean policy-change date
--                      exists in this data — all four strategy_versions run in
--                      parallel throughout Jan-May. The median-start split is
--                      the best available proxy for "before vs after".)
-- Outcome           : conversion rate = SUCCESS payment within 30 days of a
--                      daily_targeting touch, per account-campaign touch.
--
-- IDENTIFICATION STRATEGY
--   DiD estimate = (NEW,LATE - NEW,EARLY) - (OLD,LATE - OLD,EARLY)
--   This nets out any general time trend (season, macro conditions) that
--   would affect both groups equally, isolating the effect specific to the
--   strategy generation change.
--
-- KEY ASSUMPTION (parallel trends): absent the strategy change, the OLD-
--   strategy campaigns' cohort-over-cohort trend is a valid stand-in for
--   what the NEW-strategy campaigns' trend would have been. This is
--   PARTIALLY testable (we can check pre-period trends only, not literally
--   verify the counterfactual) and is the weakest link in this design —
--   see Limitations below.
--
-- CONFOUNDING FACTORS
--   - Campaign channel mix could differ between OLD/NEW cohorts by chance
--     (not explicitly matched here — a fuller version would stratify by
--     channel too).
--   - Selection: which accounts get targeted by which strategy_version is
--     set by campaign design, not randomized — a classic non-experimental
--     caveat.
--   - Attribution coverage (~17%, see Data Quality Report) limits every
--     touch-level outcome measurement here to the same subset limitation.
--
-- LIMITATIONS
--   - This is a cohort-based quasi-DiD, not a true natural experiment: no
--     single campaign is observed both before AND after a strategy switch
--     (each campaign has one fixed strategy_version for its whole life).
--   - Result should be read as "no detectable effect down to the precision
--     this design offers," not "proof of zero effect."
-- ============================================================================

WITH camp_group AS (
    SELECT campaign_id, channel,
        CASE WHEN strategy_version IN ('legacy','v1') THEN 'OLD' ELSE 'NEW' END AS strategy_gen,
        CASE WHEN start_at < (SELECT median(start_at) FROM golden_campaigns) THEN 'EARLY' ELSE 'LATE' END AS cohort
    FROM golden_campaigns
),
touched AS (
    SELECT cg.strategy_gen, cg.cohort,
           CASE WHEN p.payment_id IS NOT NULL THEN 1 ELSE 0 END AS converted
    FROM golden_daily_targeting dt
    JOIN camp_group cg ON dt.campaign_id = cg.campaign_id
    LEFT JOIN golden_payments p ON p.account_id = dt.account_id AND p.payment_status='SUCCESS'
        AND p.event_at BETWEEN dt.target_date AND dt.target_date + INTERVAL 30 DAY
)
SELECT strategy_gen, cohort, count(*) AS n_touches,
       round(100.0*avg(converted), 2) AS conversion_rate_pct
FROM touched GROUP BY 1,2 ORDER BY 1,2;

-- RESULT (computed on this dataset):
--   OLD / EARLY : 7.36%
--   OLD / LATE  : 7.50%   (Δ = +0.14pp)
--   NEW / EARLY : 7.32%
--   NEW / LATE  : 7.20%   (Δ = -0.12pp)
--   DiD estimate = (-0.12) - (+0.14) = -0.26 percentage points
--
-- INTERPRETATION: -0.26pp is within the noise band observed everywhere else
-- in this dataset (channel/segment/agent differences all sit inside a similar
-- +-0.3pp range). CONCLUSION: no economically meaningful counterfactual
-- effect is detectable from the targeting-strategy change. Had the business
-- NOT changed strategy, recovery would plausibly look statistically the same
-- as what was actually observed. Classification: Hypothesis, bounded by a
-- Strong-Evidence null result — the design cannot rule out a small effect,
-- but rules out a large one.
