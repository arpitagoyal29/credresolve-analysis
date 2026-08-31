# CredResolve Collections Analysis

Assignment: figure out if "recovery improved 11% month-on-month" is actually true, and where
CredResolve should put ₹10 Cr next.

Short version: the 11% is real if you only look at Feb vs March. Look at the whole 7 months
and recovery is basically flat — January and July brought in almost the exact same amount.
Full reasoning is in the memo.

## What's in here

- `memo/` — 2-page executive memo, the main answer
- `notebook/` — the actual analysis, step by step, with real query outputs
- `data_quality/` — every data problem I found and what I did about it
- `sql/` — the SQL, split into 4 files (cleaning, metrics, forensics, counterfactual)
- `golden_dataset/` — cleaned CSVs + a table showing raw vs. rejected vs. golden row counts
- `dashboard/` — one HTML file, single screen
- `architecture/` — how this would run as a daily pipeline in production

## Things that mattered most

The two duplicate-payment issues weren't the same problem. About 500 payments were literally
copy-pasted twice (some kind of retry bug) — those were safe to just drop. But thousands of
payment reference numbers were being reused across completely unrelated payments — different
account, different amount, sometimes months apart. If I'd deduplicated on that field like the
first issue, I'd have deleted real payments and made recovery look like it dropped 25% when it
didn't. Took a while to catch the difference.

Also found that `borrower_id` is basically garbage everywhere except the accounts table
itself — checked it against 10 different tables and the match rate was 0%. So every join in
this project goes through `account_id` instead.

And a smaller one I almost missed on a re-check: 60% of calls are routed through phone vendors
that are marked "inactive" in the vendor table, right up to the last day of data. Vendor status
field can't be trusted either.

## How to reproduce

```
duckdb collections.duckdb < sql/01_golden_dataset.sql
duckdb collections.duckdb < sql/02_metrics.sql
duckdb collections.duckdb < sql/03_forensics.sql
duckdb collections.duckdb < sql/04_counterfactual.sql
```


