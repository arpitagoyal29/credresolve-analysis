# Data Quality Report

## Raw vs. golden row counts

| Table | Raw rows | Golden rows | Dropped | Why |
|---|---:|---:|---:|---|
| payments | 25,500 | 25,000 | 500 | exact duplicate payment_id rows |
| calls | 91,350 | 90,000 | 1,350 | exact duplicate call_id rows |
| whatsapp_events | 60,600 | 60,000 | 600 | exact duplicate whatsapp_event_id rows |
| agents | 30,000 | 1,000 (keys only) | 29,000 | identity fields unusable, see below |
| everything else | — | — | 0 | no exact duplicates found |

Total exact-duplicate rows dropped: about 2,450, roughly 1% of all event rows. Small
correction on its own — doesn't explain the reported 11%. That's a separate story (see the
memo).

## Duplicate payments — turned out to be two different problems

I initially assumed "duplicate payments" meant one thing, but there were actually two, and
they need opposite fixes.

**The real duplicates:** 500 payment_id values show up twice, and when I checked, they're
exact copies — same amount, same account, same everything. Looks like a retry bug on
ingestion. Safe to drop, kept one copy of each.

**The one that isn't actually a duplicate:** I noticed payment_reference (the transaction
code) repeats a lot — about 3,700 of them show up more than once. My first instinct was to
dedupe on this too. Good thing I checked the actual rows first, because these aren't the same
payment recorded twice — they're completely different payments that happen to share a
reference number. Different account, different amount, sometimes 6+ months apart. If I'd
deduped on this field the way I did with payment_id, I would have deleted real payments
belonging to different customers, and it would have looked like recovery dropped 25% in a
month when nothing actually happened. Left payment_reference alone — kept it in the data, just
never used it as a way to identify "the same payment."

## Attribution — only 17% of payments can be traced to a campaign

I wanted to know which channel (WhatsApp, Field, Voice, SMS) is driving recovery, so I tried
joining payments to the campaign-targeting table on account + a 30-day window. Only 3,012 of
17,880 successful payments matched anything — under 17%. The other 83% of the money coming in
has no record of which campaign or channel touch led to it.

That's a bigger deal than it sounds. It means any conclusion about "channel X works better"
is really only about the 17% we can see, not the whole picture. I flagged this everywhere it
matters, including in the ₹10 Cr recommendation.
## Timezone — can't actually trust it

Calls have a timezone field, and I wanted to use it to check if calling at certain hours
works better. Turns out it's not reliable. For the same account, calls show up tagged with 2
or sometimes all 3 different timezones — Kolkata, Dubai, UTC — with no pattern to it. And when
I plotted call volume by hour of day, it's almost perfectly flat across all 24 hours,
including 3am. Real call centers don't call at 3am nearly as often as 2pm, so this told me the
hour/timezone data just isn't trustworthy enough to draw conclusions from. I kept the raw
field in the golden data for anyone who wants to dig further, but I didn't use it for any
"best time to call" analysis.

## Disposition codes changed mid-stream

The call outcome codes (disposition_code) aren't consistent across the whole dataset. The
older schema version has both "PROMISE_TO_PAY" and "PTP" as separate codes, which are clearly
meant to be the same thing — the newer schema versions only use "PTP". If I hadn't merged
these, any month-over-month PTP count would look artificially low or high depending on which
code was in use that month. Mapped both to "PTP" in the golden layer.

## Telephony vendors — a good chunk of this dataset doesn't match its own vendor table

This one I actually missed on my first pass and only caught on a recheck. The vendor table
lists 15 vendors, 9 of them marked "inactive." But when I checked which vendor actually routed
each call, 60% of all calls (54,089 out of 90,000) went through a vendor marked inactive — and
this wasn't just old data from before they went inactive, it was happening right up through
the last days in the dataset. So the "status" field in the vendor table just doesn't reflect
what's actually happening operationally. Didn't use vendor status for any comparison after
finding this.

## Agent identity is basically unusable — and it's not just agents

The agents table has 30,000 rows but only 1,000 unique agent IDs, meaning each agent shows up
about 30 times. I expected that to be a history of status changes over time. Instead, the
name, employee code, and team attached to a single agent ID change almost every single row —
one agent ID showed up under 15 different names. So there's no way to reliably say "this
agent has been here X months" or "this agent is on team Y." I kept agent_id as a bare key
since it's used consistently to link calls/payments/etc., but I didn't try to attach a real
identity to it — any attempt to "guess" the true name or tenure would just be making something
up.

Then I found the same pattern somewhere I didn't expect: borrower_id. Every event table
(calls, payments, PTPs, field visits, everything) has a borrower_id field, and I assumed it'd
at least be internally consistent. Checked it against the accounts table, which is the one
place borrower_id should be reliable — the match rate was 0.0% across all ten tables I
checked. Not "mostly wrong," completely scrambled, statistically no better than random. So the
only ID that actually works for connecting anything in this dataset is account_id. I dropped
borrower_id from every table in the golden layer and rebuilt any borrower-level lookups
through account_id → accounts → borrowers instead.
## Portfolio mix — didn't shift

One theory worth ruling out: maybe the business just started chasing easier debt, which would
make recovery look better without anything actually improving. Checked risk segment mix and
average DPD, month by month — both stayed in a tight band the whole time (segment shares
24–26% every month, average DPD around 55–57 days). No shift. This isn't the explanation.

## Denominator — daily_targeting isn't the full picture

Wanted to check if the "population" used to calculate conversion rates was being quietly
shrunk to make numbers look better (dropping hard accounts from the denominator, basically).
The status mix in daily_targeting (queued/contacted/skipped/expired) stayed flat at roughly
25% each, every month — no evidence of manipulation there.

But I found a different problem with using daily_targeting as "the denominator" at all: most
accounts only show up in it for 1 or 2 months out of the 7-8 month window, not consistently.
Combined with the attribution issue above (only 17% of payments link back to it), it's really
a partial log, not a full census of who's being worked. So for anything I called a
"portfolio-wide" rate, I used the accounts table instead, filtered to non-closed accounts —
not daily_targeting.

## Geography and how many times someone's called

Checked recovery by state and it tracks account volume, not anything more interesting — no
state stands out as a real driver. Also checked whether calling an account more times (1st
attempt through 7th) changes the odds of getting paid — it doesn't, conversion stays flat
around 7%, regardless of attempt number.

Two fields the assignment asked about — client and language — don't exist anywhere in the 17
source tables. Nothing to check there, not a gap I skipped, just not present in the data.

## The thing I'd flag for further digging: Simpson's paradox

This is the one finding I think is genuinely worth someone following up on. The overall
recovery trend is flat — January and July are basically identical. But when I broke that same
conversion number down by risk segment, every single segment (NPA, High, Medium, Low) actually
shows a real decline from January to July, somewhere between 1.5 and 2.5 percentage points
each. That's not a contradiction, exactly — the segment-level number is measured on the 17%
of payments I could actually attribute to a campaign, while the flat overall number uses all
payments regardless of attribution. But it's the one spot in this whole analysis where two
honestly-calculated numbers seem to disagree, and I can't fully explain why with the data I
have. My best guess is that average payment size per success went up enough to offset fewer
successes, but I can't confirm that without the missing 83%. This is the strongest argument
for fixing attribution tracking before the business makes any big channel-based spending
decisions.

## What I didn't try to "fix"

Two things I deliberately left alone instead of guessing at a fix: the real identity behind a
scrambled agent_id, and the real borrower behind a scrambled borrower_id. Both would require
made-up assumptions dressed up as data cleaning. I flagged both as source-system bugs that
Engineering should look at, rather than pretending I solved them with clever SQL.
