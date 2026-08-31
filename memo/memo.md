# CredResolve Collections Performance — Executive Memo

Prepared for leadership review. Data window: Jan–Aug 2026 (Aug is partial, excluded from trend numbers).

## What happened

The number going around is "recovery improved 11% month-on-month." That's not wrong, exactly
— it's just not the whole story. It only holds up if you compare February to March.

| Comparison | Growth | What it actually means |
|---|---|---|
| Feb → Mar (one month) | +11.11% | The number everyone's seen. Correct, as far as it goes. |
| Jan → Mar (two months) | +1.05% | Most of that "gain" disappears once you include Feb's dip. |
| Jan → Jul (full window) | ~0% | January and July recovered almost the exact same amount. |

Once I cleaned out about 500 duplicate payment records (a re-ingestion bug, roughly 2% of
rows), the real picture is recovery bouncing between ₹170–190 Cr a month with no real
direction for seven months straight. Contact rate has stayed around 20%. PTP kept-rate has
stayed around 49–52%. Nothing has actually moved.

## Why

Honestly, the most likely explanation is simpler than it sounds: most dashboards default to
showing "vs. last month," and Feb–March happened to be the best-looking pair in a series
that's mostly just noise. That's not someone lying — it's just what you get if nobody plots
the full trend line.

A few things I checked and ruled out:
- Portfolio mix hasn't shifted — risk segments and average DPD look the same in January as
  in July.
- Channel mix and per-contact conversion (~8% across Field, Voice, SMS, WhatsApp) are also
  stable — no channel took off or fell off.
- The targeting-strategy versions running in parallel (legacy through v3) show conversion
  rates within 0.2 points of each other. Whatever changed in strategy didn't move the needle
  in a way I can detect.

One thing I can't rule out: only 17% of successful payments can actually be traced back to a
specific campaign or channel. The other 83% just don't have that link in the source data. So
any channel-level claim — including the recommendation below — is built on a fairly small,
possibly unrepresentative slice.

Also worth flagging: 60% of calls are going through telephony vendors that are currently
marked "inactive" in the vendor master table, and this isn't a one-off — it's been happening
the whole way through, including the last few days of data. Probably stale metadata rather
than a real routing issue, but it means I can't trust vendor-level quality comparisons until
that's fixed.

## Is the 11% real?

Yes, technically. But it's one data point being read as a trend, and it isn't one. If I had to
put it in one sentence: recovery is flat, not improving, and the 11% is what you get from
zooming into the best two-week window in an otherwise flat line.

## How confident am I

Pretty confident recovery is flat overall — checked it three different ways and it holds up.
Less confident about *why* any single channel or agent looks the way it does, because of that
83% attribution gap mentioned above.

One thing that's bugging me and worth someone looking into further: when I broke the
conversion rate down by risk segment, every single segment (NPA, High, Medium, Low) shows a
real decline from January to July — even though the total money recovered stayed flat. That's
not necessarily a contradiction (this is measured on the smaller 17%-attributable slice, not
the full picture), but it's the clearest sign that fixing the attribution gap would actually
tell us something new, not just confirm what we already know.

## What should we do with the ₹10 Cr

**My recommendation: WhatsApp / digital engagement.** Moderate confidence, not high.

The reasoning: every channel converts at roughly the same rate per contact (~8%). Field
visits and live agent calls cost a lot more per attempt than a WhatsApp message. If the odds
of success are the same either way, the cheaper channel lets you buy more attempts with the
same ₹10 Cr — and more attempts at equal odds means more total recovery.

I don't have real cost numbers for this dataset, so I'm using rough industry placeholders
(₹1/WhatsApp message, ₹15–25/voice attempt, ₹400–600/field visit — Finance should confirm
these before anyone commits real budget). With those assumptions, ₹10 Cr buys roughly 10 Cr
additional WhatsApp attempts a year, and at 8% conversion and ~₹6,600 average recovery per
success, that's plausibly ₹500 Cr–₹1,000+ Cr in incremental recovery — a wide range, and it'll
shrink once you hit diminishing returns from running out of people to message.

Downside case: if digital genuinely converts worse than a live agent on the hardest accounts
(high DPD, NPA) — which I can't test given the attribution gap — actual returns could be a lot
lower than this estimate.

Before committing the full amount, I'd run a 4–6 week pilot: extra WhatsApp touches on part of
the portfolio, a held-out control group, and proper tracking of which payment came from which
touch. Costs under ₹10 lakh and fixes the attribution problem at the same time.

## Expected financial impact

Real modeling needs the pilot above and confirmed cost numbers from Finance. Directionally,
shifting spend toward the channel with equal conversion and lower cost per attempt should be
positive for recovery — but treat the number above as a wide-range estimate, not a forecast
anyone should hold me to.
