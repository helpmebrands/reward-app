# Domain model

The pure core of HelpMe Reward: cards, benefits, cycles, claims, and the selectors that resolve them into what every screen renders. Nothing in `src/domain/` imports a framework, which is what makes it the part worth testing.

Types live in `src/domain/types.ts`. Everything else here is derived from `AppData`, which is `{ cards, benefits, claims, settings }`.

## Calendar dates, not timestamps

Dates that name a day are `YYYY-MM-DD` strings (`IsoDate`); instants such as when a claim was recorded are full ISO-8601 strings (`IsoInstant`). "September 2026" must not shift when the user crosses a timezone.

All calendar arithmetic in `src/domain/dates.ts` computes via `Date.UTC`, which has no DST transitions. Using local-time `Date` objects silently shifts dates by a day twice a year in most timezones. Two rules follow:

- [[src/domain/dates.ts#addMonths]] clamps the day to the target month, so Jan 31 + 1 month is Feb 28, never March 3.
- [[src/domain/dates.ts#todayIso]] is the one exception: it reads the *local* clock, because the user experiences the issuer's calendar dates locally. At 23:30 local on the 16th, it is still the 16th even if UTC says the 17th.

ISO dates are zero-padded, so lexical comparison is chronological ([[src/domain/dates.ts#compareIsoDate]]).

## Card

A card belongs to one person in the household. The `holder` field is what distinguishes two of the same product; `nickname` wins over `issuer product` in the UI when set.

- `anniversaryOn` anchors anniversary cycles and the annual-fee countdown. Only month and day matter for recurrence.
- `annualFeeCents` is what the Cards and Value screens measure captured value against ([[domain#Card value and the cardmember year]]).
- `muted` silences every credit on the card without losing their state. `archived` hides the card and its credits from every selector.
- `last4` is display only; a full PAN is never stored.

## Benefit

A benefit is one recurring credit on one card: a value in cents released per cycle, a cadence, an anchor, and the enrolment state that decides whether it is spendable at all.

Fields with behaviour behind them:

- `cadence` and `anchor` decide the window. See [[domain#Benefit#Cadence]] and [[domain#Benefit#Cycle anchors]].
- `enrollmentRequired` with no `enrolledAt` makes the credit `locked` ([[domain#Status ladder#Locked is not unclaimed]]).
- `merchant` (e.g. "Uber", "Resy") is the key for [[domain#Overlaps]] across issuers.
- `muted` silences reminders for this credit only; `lastCallOnly` collapses its ladder to the final rung ([[reminders#The ladder]]).
- `active: false` keeps history but stops tracking.

### Cadence

Five cadences: `monthly`, `quarterly`, `semiannual`, `annual`, and `manual`. The first four span 1, 3, 6 and 12 months. `manual` never recurs.

`manual` covers credits no cycle can track, such as Global Entry every four years. They are listed, given a stand-in "Untracked" window, and never counted as at risk, never reminded about, and never entered in the missed ledger. [[src/domain/cycles.ts#annualValueCents]] counts them once rather than once per notional year.

### Cycle anchors

A recurring cycle is measured from one of two origins, recorded per benefit rather than inferred from the cadence, because getting it wrong is the commonest way a credit is lost.

- `calendar`: the Gregorian calendar. [[src/domain/cycles.ts#anchorDateFor]] uses January 1st of the card's anniversary year as the origin, which puts quarters on Jan/Apr/Jul/Oct and halves on Jan/Jul, the windows issuers actually use.
- `anniversary`: the day the account was opened, so the "cardmember year" of a Sapphire Reserve travel credit.

The labels differ too ([[src/domain/cycles.ts#cycleLabel]]): calendar windows get issuer shorthand ("Sep 2026", "Q3 2026", "H2 2026", "2026"), while anniversary windows are labelled by start date ("from Mar 14 2026") because a cardmember quarter is not Q3.

## Cycle

A cycle is the concrete window in which a benefit can be used: inclusive `start` and `end`, a `label`, and a `key` equal to `start` that claims attach to. Cycles are derived, never stored.

[[src/domain/cycles.ts#cycleFor]] finds the cycle containing a date by walking from the anchor in whole cycle-lengths. Because month arithmetic clamps, the naive `(years * 12 + months) / span` step count can land in the wrong window at month ends, so the step is corrected by comparison, bounded to at most one correction in each direction.

The invariant that matters, and that the tests assert: every day belongs to exactly one cycle, with no gaps and no overlaps, even for an anniversary on the 31st across short months.

Helpers: [[src/domain/cycles.ts#nextCycle]], [[src/domain/cycles.ts#previousCycle]], [[src/domain/cycles.ts#cyclesBetween]] (for reminder scheduling and history), and [[src/domain/cycles.ts#closedCyclesBefore]] (for the missed ledger). [[src/domain/cycles.ts#daysRemainingIn]] returns 0 on the final day and negative once closed.

## Claims

A claim records one use of a credit within one cycle. Partial claims are the normal case, several claims per cycle are summed, and a claim is keyed by `benefitId` plus `cycleKey`.

Rules the store enforces ([[src/stores/app.tsx#AppProvider]]):

- Claiming without an amount takes what is *left*, not the face value, so a second claim on a partly used credit cannot overshoot.
- `unclaim` removes every claim against one cycle. That is what the snackbar's Undo calls.
- Deleting a benefit or card deletes its claims with it.

Claims are indexed once per resolve ([[src/domain/selectors.ts#indexClaims]]) so resolving every credit stays linear.

## Status ladder

Every benefit instance sits on exactly one rung: `locked`, `manual`, `use_soon`, `available`, `captured` or `missed`. The status is computed, never stored.

Precedence, from `statusFor` in `src/domain/selectors.ts`:

1. `captured` when claimed cents reach the value. This outranks everything, including locked: a credit that was used is used.
2. `manual` for untracked cadences.
3. `locked` when enrolment is required and unconfirmed.
4. `missed` when the window has closed.
5. `use_soon` when the window closes within `settings.useSoonDays` (default [[src/domain/types.ts#USE_SOON_DAYS]], 30), otherwise `available`.

Instances sort by [[src/domain/selectors.ts#compareByUrgency]]: status order (use soon, available, locked, manual, captured, missed), then soonest deadline, then most money at stake.

Only `use_soon` and `available` are "claimable" ([[src/domain/selectors.ts#isClaimable]]), and that is the set the headline number and the next-reset date are built from.

### Locked is not unclaimed

A credit behind an unticked enrolment box cannot be spent. Treating it as unclaimed would tell the user to do something they cannot do, so it is counted separately, excluded from the headline, and never dunned.

Consequences elsewhere:

- Today shows locked credits in their own section, below the headline.
- The Credits screen keeps `lockedCents` as its own figure ([[domain#The four totals]]).
- Reminders only mention locked credits when the user has opted into enrolment reminders, and then lead with the blocker rather than the spend ([[reminders#Schedule construction#Notification copy]]).
- The detail sheet offers "I've enrolled — unlock this credit" instead of a spend action. Confirming sets `enrolledAt`; revoking clears it.

## The four totals

Claimable, locked, captured and missed are four different quantities. Money you can still get and money you have already lost are never summed into one number.

[[src/domain/selectors.ts#totalsFor]] returns them side by side:

| Figure | Meaning |
| --- | --- |
| `claimableCents` | Open and spendable. Today's headline. |
| `lockedCents` | Behind an enrolment box. Excluded from claimable on purpose. |
| `capturedCents` | Already used this cycle. |
| `missedCents` | Windows that closed unused ([[domain#Missed ledger]]). |

## Overlaps

An overlap is the same credit carried by two cards in the household, so that one booking cannot draw on both. It is the design's premise made visible.

[[src/domain/selectors.ts#findOverlaps]] groups claimable and locked instances by `merchant` when set, otherwise by credit name, both lower-cased. A group is an overlap only when it spans at least two distinct cards: two rows on the *same* card are two credits, not an overlap. Matching by merchant first is what lets "Uber Cash" on a Platinum match "Rideshare Credit" on a Reserve, while name alone would collide across issuers using the same wording.

Each group reports `sameProduct` (the same issuer and product held twice) and the combined unclaimed value. Today shows the top three; the compare sheet shows one side by side and stops short of ranking the two people.

## Missed ledger

A closed cycle with less claimed than its value is a miss for the shortfall. The ledger is computed from claims rather than stored, so it is always consistent with what the user actually logged.

[[src/domain/selectors.ts#missedCycles]] walks back through closed cycles (24 by default) and stops at the card's `createdAt`: the app cannot know whether a credit was used before it started tracking, so it never blames the user for windows that closed earlier. Manual credits have no window to miss.

Two views are built on it:

- [[src/domain/selectors.ts#biggestLeaks]] groups repeated misses of one credit into a single line ("Uber Cash × 8, Jan – Aug 2026, $120"), because a habit is fixable while eight $15 rows are noise.
- [[src/domain/selectors.ts#monthlyTotals]] bins captured by the month a claim was *logged* and missed by the month the window *closed*, which is when the money actually went away.

## Card value and the cardmember year

A card is judged against its own annual fee, over its own cardmember year. Six cards with six fees cannot share a dollar axis, so the Value screen plots captured value as a percentage of fee, where 100% is break-even for every card.

[[src/domain/selectors.ts#summarizeCard]] builds the per-card figures. The cardmember year is found by reusing the cycle maths with a stand-in annual, anniversary-anchored benefit ([[src/domain/selectors.ts#cardYearStart]]), and `capturedCents` is the sum of claims logged since that date ([[src/domain/selectors.ts#claimedThisCardYear]]). `netCents` is captured minus fee; `feeProgress` is the break-even bar.

This is why the Value tab and the Cards tab can disagree: Value covers the last nine calendar months, while each card's figure covers only its own fee period. A credit only pays for the fee it was issued against.

## Form rules

`src/domain/validation.ts` holds the rules the editors apply, as pure functions returning the sentence to show or null. Each sentence says what to enter, not what went wrong.

- [[src/domain/validation.ts#requiredError]]: a text field must not be blank; the caller supplies the sentence.
- [[src/domain/validation.ts#moneyError]] and [[src/domain/validation.ts#positiveMoneyError]]: an amount is a number, at or above zero for a fee or a threshold, above zero for a credit's value. [[src/domain/validation.ts#parseMoney]] turns the typed text into whole cents.
- [[src/domain/validation.ts#anniversaryError]]: the cardmember year start is a real calendar date.
- [[src/domain/validation.ts#enrollmentUrlError]]: an enrolment page, if given, is an http or https URL.

## Card catalogue

`src/domain/catalog.ts` holds starting templates for known cards. It is an onboarding aid, not a source of truth: issuers change terms constantly, so everything it creates becomes an ordinary editable benefit and the add-card flow says so.

`enrollmentRequired` is the field worth getting right in a template, since it decides whether a credit lands as locked or spendable. [[src/domain/catalog.ts#benefitsFromTemplate]] stamps template entries into real benefits with fresh ids; a `blank` template exists for cards the catalogue does not know.
