# Domain model

The pure core of HelpMe Reward: cards, benefits, cycles, claims, and the selectors that resolve them into what every screen renders.

The rules are pure functions of the data with no framework behind them, which is what makes this the part worth testing. They live in `packages/domain`, shared by the Flutter app and the service tier, ported one module at a time with its tests first from the PWA retired in #174.

Types live in `packages/domain/lib/src/types.dart`. Everything else here is derived from `AppData`, which is `{ cards, benefits, claims, settings }`.

## Calendar dates, not timestamps

Dates that name a day are `YYYY-MM-DD` strings (`IsoDate`); instants such as when a claim was recorded are full ISO-8601 strings (`IsoInstant`). "September 2026" must not shift when the user crosses a timezone.

All calendar arithmetic (`packages/domain/lib/src/dates.dart`) computes in UTC, which has no DST transitions. Local-time date objects silently shift dates by a day twice a year in most timezones. Two rules follow:

- `addMonths` clamps the day to the target month, so Jan 31 + 1 month is Feb 28, never March 3.
- `todayIso` is the one exception: it reads the *local* clock, because the user experiences the issuer's calendar dates locally. At 23:30 local on the 16th, it is still the 16th even if UTC says the 17th.

ISO dates are zero-padded, so lexical comparison is chronological (`compareIsoDate`).

## Card

A card belongs to the household, not to a person. Its display name (`cardLabel`) is its optional `label`, or `issuer product` when there is none, and it must be unique within the household.

Two of the same product are told apart by their labels. `defaultLabel` proposes the first free "American Express Platinum (n)" from 1 for a duplicate, and the proposal is stored, so deleting a card renames nothing. `labelError` refuses a label, or a blank one, whose display name another card already shows, ignoring case and surrounding space. The Dart domain dropped the PWA's `holder` and `nickname` (#208); the frozen PWA keeps them, and the Dart codec ignores `holder` when it reads the PWA's sample.

- `anniversaryOn` anchors anniversary cycles and the annual-fee countdown. Only month and day matter for recurrence.
- `annualFeeCents` is what the Cards and Value screens measure captured value against ([[domain#Card value and the cardmember year]]).
- `archived` hides the card and its credits from every selector. Silencing a card is a member's choice, not the card's ([[domain#Member preferences]]).
- `last4` is display only; a full PAN is never stored.
- `kind` says whether it is a `personal` or a `business` product. Classification only: the card editors offer the choice, the Cards screen marks business cards, and a template's kind lands on the card it creates. The add-card catalogue can be filtered by kind ([[domain#Catalogue filter]]); the Cards screen cannot. A snapshot from before `kind` existed loads with every card `personal` (`appDataFromJson`).

## Member preferences

The household's cards, credits and claims are shared by its members; reminder settings and mutes are not, so `MemberPreferences` holds one member's.

They are whether reminders are on, the time of day, the value floor, the annual-fee and enrolment switches, and the muted card and credit ids.

`isMuted(benefit)` is true when the member muted the credit or its card. `buildSchedule(data, prefs)` and `currentInstances(data, on, prefs)` read them, so one household scheduled for two members gives two schedules, and one member's mute leaves the household's data untouched (#209). The Dart domain dropped the PWA's `Card.muted`, `Benefit.muted` and `Settings.notifications`; the codec ignores them in the PWA's sample. `defaultMemberPreferences` are the PWA's defaults: off, 09:00, a $1 floor, both switches on, nothing muted.

## Benefit

A benefit is one recurring credit on one card: a value in cents released per cycle, a cadence, an anchor, and the enrolment state that decides whether it is spendable at all.

Fields with behaviour behind them:

- `cadence` and `anchor` decide the window. See [[domain#Benefit#Cadence]] and [[domain#Benefit#Cycle anchors]].
- `enrollmentRequired` with no `enrolledAt` makes the credit `locked` ([[domain#Status ladder#Locked is not unclaimed]]).
- `spendThresholdCents` is the second kind of lock: spend the issuer asks for in a year before the credit opens (Business Platinum's $250K credits, the Dell bonus). Until `spendMetAt` falls inside the current year the credit is `locked` for spend ([[domain#Status ladder#A spend threshold is the other lock]]).
- `merchant` (e.g. "Uber", "Resy") is the key for [[domain#Overlaps]] across issuers.
- `lastCallOnly` collapses its ladder to the final rung ([[reminders#The ladder]]). Silencing a credit is a member's choice ([[domain#Member preferences]]).
- `optedOutAt` marks a credit the household will never use (an Oura ring, Equinox). It stays on the card but leaves every list and total except its own ([[domain#Status ladder#Opted out is a choice, not a status of the window]]). `trackedFrom` is the day tracking resumed after an opt-out.
- `active: false` is kept only for a credit that had already ended when it was added or paused. The codec loads a legacy paused credit that had not ended by its `updatedAt` as opted out at that instant.
- `endsOn` is the last day the credit can be used, for credits the issuer has announced an end to (Grubhub, Instacart). The final window is clamped to it and nothing follows ([[domain#Cycle]]); afterwards the credit is skipped the way an inactive one is, while its final shortfall stays in the [[domain#Missed ledger]]. `annualValueCents` is not prorated for a credit ending mid-year.

### Cadence

Six cadences: `monthly`, `quarterly`, `semiannual`, `annual`, `rolling` and `manual`. The first four span 1, 3, 6 and 12 months from an anchor; `rolling` spans `intervalMonths` from the last claim; `manual` never recurs.

`rolling` is for credits the issuer counts from the last reimbursement, such as Global Entry every 48 months. The anchor is ignored: the window is open ("Eligible now") until a claim closes it for `intervalMonths`, so the app never suggests a credit the issuer would refuse ([[domain#Cycle]]). It is never at risk, never reminded about and never in the missed ledger, and `annualValueOf` amortises it: $120 every 48 months is $30 a year.

`manual` covers credits no cycle can track at all. They are listed, given a stand-in "Untracked" window, and never counted as at risk, never reminded about, and never entered in the missed ledger. `annualValueOf` counts them once rather than once per notional year.

### Cycle anchors

A recurring cycle is measured from one of two origins, recorded per benefit rather than inferred from the cadence, because getting it wrong is the commonest way a credit is lost.

- `calendar`: the Gregorian calendar. `anchorDateFor` uses January 1st of the card's anniversary year as the origin, which puts quarters on Jan/Apr/Jul/Oct and halves on Jan/Jul, the windows issuers actually use.
- `anniversary`: the day the account was opened, so the "cardmember year" of a Sapphire Reserve travel credit.

The labels differ too (`cycleLabel`): calendar windows get issuer shorthand ("Sep 2026", "Q3 2026", "H2 2026", "2026"), while anniversary windows are labelled by start date ("from Mar 14 2026") because a cardmember quarter is not Q3.

## Cycle

A cycle is the concrete window in which a benefit can be used: inclusive `start` and `end`, a `label`, and a `key` equal to `start` that claims attach to. Cycles are derived, never stored.

`cycleFor` finds the cycle containing a date by walking from the anchor in whole cycle-lengths. Because month arithmetic clamps, the naive `(years * 12 + months) / span` step count can land in the wrong window at month ends, so the step is corrected by comparison, bounded to at most one correction in each direction.

The invariant that matters, and that the tests assert: every day belongs to exactly one cycle, with no gaps and no overlaps, even for an anniversary on the 31st across short months.

A rolling credit's window comes from the claim ledger, which `cycleFor` takes as its last argument. The open window is keyed by the day the card was added, or the day after the last closed window; the first claim recorded under that key closes it to the claim day plus `intervalMonths` less a day, labelled "until Sep 2030", and a new open window keys from the day after. Keys never move, so a claim always finds its window. `nextCycle` and `previousCycle` are null for it, since only a claim opens the next.

A credit with `endsOn` has its final window's `end` clamped to that day, and `cycleFor` returns null once the day is past (`hasEnded`), so `nextCycle`, `cyclesBetween` and the reminder schedule stop on their own. `closedCyclesBefore` still starts from the final window once it has passed, which is how the ledger keeps its shortfall.

Helpers: `nextCycle`, `previousCycle`, `cyclesBetween` (for reminder scheduling and history), and `closedCyclesBefore` (for the missed ledger). `daysRemainingIn` returns 0 on the final day and negative once closed.

## Claims

A claim records one use of a credit within one cycle. Partial claims are the normal case, several claims per cycle are summed, and a claim is keyed by `benefitId` plus `cycleKey`.

Rules the app enforces (in `AppStore`):

- Claiming without an amount takes what is *left*, not the face value, so a second claim on a partly used credit cannot overshoot.
- `unclaim` removes every claim against one cycle; `removeClaim` removes one. The snackbar's Undo and the sheet's Remove both remove the one claim just made.
- Deleting a benefit or card deletes its claims with it.

Claims are indexed once per resolve (`indexClaims`) so resolving every credit stays linear.

## Status ladder

Every benefit instance sits on exactly one rung: `opted_out`, `locked`, `manual`, `use_soon`, `available`, `captured` or `missed`. The status is computed, never stored.

Precedence, from `statusFor` in `packages/domain/lib/src/selectors.dart`:

0. `opted_out` when `optedOutAt` is set. This outranks everything, captured included: the household has said it will not use the credit.
1. `captured` when claimed cents reach the value. This outranks everything, including locked: a credit that was used is used.
2. `manual` for untracked cadences.
3. `locked` when enrolment is required and unconfirmed, or a spend threshold is not yet met (`lockReason` says which; enrolment outranks spend).
4. `available` for a `rolling` credit, whatever the day: its window has no deadline to miss, so it is never `use_soon` or `missed`.
5. `missed` when the window has closed.
6. `use_soon` when the window closes within `settings.useSoonDays` (default `useSoonDays`, 30), otherwise `available`.

Instances sort by `compareByUrgency`: status order (use soon, available, locked, manual, captured, missed, opted out), then soonest deadline, then most money at stake.

Only `use_soon` and `available` are "claimable" (`isClaimable`), and that is the set the headline number and the next-reset date are built from.

### Locked is not unclaimed

A credit behind an unticked enrolment box cannot be spent. Treating it as unclaimed would tell the user to do something they cannot do, so it is counted separately, excluded from the headline, and never dunned.

Consequences elsewhere:

- Today shows locked credits in their own section, below the headline.
- The Credits screen keeps `lockedCents` as its own figure ([[domain#The five totals]]).
- Reminders only mention locked credits when the user has opted into enrolment reminders, and then lead with the blocker rather than the spend ([[reminders#Schedule construction#Notification copy]]).
- The detail sheet offers "I've enrolled — unlock this credit" instead of a spend action. Confirming sets `enrolledAt`; revoking clears it.

### Opted out is a choice, not a status of the window

Some credits will never be used. Opting out keeps the credit on its card but takes it off every list and out of every figure except its own, so what is left reflects what the household will actually spend.

The flag lives on the credit on one card: two people with their own Platinum opt out on their own card. Consequences:

- `totalsFor` counts its annual value in `optedOutCents` and nowhere else ([[domain#The five totals]]).
- `missedCycles` skips it, and `buildSchedule` never reminds about it ([[reminders#Schedule construction]]).
- `summarizeCard` counts it in the card's potential value but not its usable value ([[domain#Card value and the cardmember year]]).
- The mobile store leaves it out of `instances`, so no screen list shows it.
- Reactivating clears `optedOutAt` and sets `trackedFrom` to that day, so the windows that closed while it was opted out are never counted as missed ([[domain#Missed ledger]]).

### A spend threshold is the other lock

A credit gated behind a year's spend (Business Platinum's $250K credits, the Dell $1,000 bonus, IHG's $20K credit) is money most cardholders will never see, so it is locked and left out of every value figure until the user says the spend is reached.

`lockReason` returns `spend` when `spendThresholdCents` is set and `spendMetAt` does not fall inside the credit's current year. "Current year" follows the anchor: the calendar year for `calendar`, the cardmember year for `anniversary`, found by running `cycleFor` with an annual cadence. Stated assumption: the credit unlocks in the year the spend is met, not the year after.

Consequences:

- Today's locked section says which lock applies: "Locked behind enrolment", "Locked behind a spend threshold", or both.
- The detail sheet reads "Unlocks after $250,000 spend this year" and offers "I've reached it — unlock", which sets `spendMetAt`; revoking clears it.
- `summarizeCard` counts nothing for a spend-locked credit in `annualValueCents`, and `templateAnnualValueCents` leaves gated entries out of the catalogue price.
- Reminders never mention a spend-locked credit, whatever the enrolment-reminder setting: no notification can reach a spend threshold ([[reminders#Schedule construction]]).

## The five totals

Claimable, locked, captured, missed and opted out are five different quantities. Money you can still get and money you have already lost are never summed into one number.

`totalsFor` returns them side by side:

| Figure | Meaning |
| --- | --- |
| `claimableCents` | Open and spendable. Today's headline. |
| `lockedCents` | Behind an enrolment box. Excluded from claimable on purpose. |
| `capturedCents` | Already used this cycle. |
| `missedCents` | Windows that closed unused ([[domain#Missed ledger]]). |
| `optedOutCents` | A year's value of the opted-out credits, which no other figure counts. |

## Overlaps

An overlap is the same credit carried by two cards in the household, so that one booking cannot draw on both. It is the design's premise made visible.

`findOverlaps` groups claimable and locked instances by `merchant` when set, otherwise by credit name, both lower-cased. A group is an overlap only when it spans at least two distinct cards: two rows on the *same* card are two credits, not an overlap. Matching by merchant first is what lets "Uber Cash" on a Platinum match "Rideshare Credit" on a Reserve, while name alone would collide across issuers using the same wording.

Each group reports `sameProduct` (the same issuer and product held twice) and the combined unclaimed value. Today shows the top three; the compare sheet shows one side by side and stops short of ranking the two people.

## Missed ledger

A closed cycle with less claimed than its value is a miss for the shortfall. The ledger is computed from claims rather than stored, so it is always consistent with what the user actually logged.

`missedCycles` walks back through closed cycles (24 by default) and stops at the card's `createdAt`: the app cannot know whether a credit was used before it started tracking, so it never blames the user for windows that closed earlier. It also skips opted-out credits, and for a reactivated credit every window that closed before its `trackedFrom`. Manual credits have no window to miss, and rolling ones close only by claim, so neither appears. A credit that has ended keeps its final, clamped window in the ledger.

Two views are built on it:

- `biggestLeaks` groups repeated misses of one credit into a single line ("Uber Cash × 8, Jan – Aug 2026, $120"), because a habit is fixable while eight $15 rows are noise.
- `monthlyTotals` bins captured by the month a claim was *logged* and missed by the month the window *closed*, which is when the money actually went away.

## Card value and the cardmember year

A card is judged against its own annual fee, over its own cardmember year. Six cards with six fees cannot share a dollar axis, so the Value screen plots captured value as a percentage of fee, where 100% is break-even for every card.

`summarizeCard` builds the per-card figures. The cardmember year is found by reusing the cycle maths with a stand-in annual, anniversary-anchored benefit (`cardYearStart`), and `capturedCents` is the sum of claims logged since that date (`claimedThisCardYear`). `netCents` is captured minus fee; `feeProgress` is the break-even bar.

A card has two annual values. `potentialValueCents` is every credit the card gives, opted-out ones included and spend-gated ones left out; `annualValueCents` is the usable value, without the opted-out credits, and is what the verdict is judged on. `optedOutCents` is the difference.

This is why the Value tab and the Cards tab can disagree: Value covers the last nine calendar months, while each card's figure covers only its own fee period. A credit only pays for the fee it was issued against.

## Form rules

`packages/domain/lib/src/validation.dart` holds the rules the editors apply, as pure functions returning the sentence to show or null. Each sentence says what to enter, not what went wrong.

- `requiredError`: a text field must not be blank; the caller supplies the sentence.
- `moneyError` and `positiveMoneyError`: an amount is a number, at or above zero for a fee or a threshold, above zero for a credit's value. `parseMoney` turns the typed text into whole cents.
- `anniversaryError`: the cardmember year start is a real calendar date.
- `endsOnError`: a credit's end date, if given, is a real calendar date; blank means it has none.
- `intervalMonthsError`: a rolling credit's months between claims is a whole number above zero; every other cadence ignores it.
- `enrollmentUrlError`: an enrolment page, if given, is an http or https URL.

## Card catalogue

`packages/domain/lib/src/catalog.dart` holds starting templates for known cards: an onboarding aid, not a source of truth. Issuers change terms constantly, so everything it creates becomes an ordinary editable benefit and the add-card flow says so.

The file was generated from the PWA's TypeScript list. Since #210 it is edited by hand, and since #174 it is the only copy; its templates carry stable credit ids: `<template id>/<slug of the name>`, such as `amex-gold/uber-cash`. It seeds version 1 of the service tier's catalogue ([[domain#Catalogue versions]]). Icons are Phosphor names in kebab-case (`car-profile`), the form the PWA's icon component takes.

`enrollmentRequired` is the field worth getting right in a template, since it decides whether a credit lands as locked or spendable. `spendThresholdCents` is the other: a gated entry is copied onto the benefit and left out of the template's annual value, so a card's catalogue price is what an ordinary cardholder can reach. A `rolling` entry carries `intervalMonths` and is priced at its amortised value; every Global Entry entry is one, at 48 months. An entry whose terms name a last day carries `endsOn`. Each template names its `kind`, which the add-card flow copies onto the new card: Business Platinum is `business`, everything else including `blank` is `personal`. `benefitsFromTemplate` stamps template entries into real benefits with fresh ids; a `blank` template exists for cards the catalogue does not know.

## Catalogue versions

A card template changes over time, so the catalogue keeps versions of it, and a card linked to a template takes its terms from them rather than holding copies (`packages/domain/lib/src/catalog_versions.dart`).

A `TemplateVersion` is a whole `CardTemplate` with its `version` and `effectiveFrom`; `versionInForce(versions, date)` is the latest whose date has passed. A linked card stores `templateId` and each linked benefit `templateBenefitId`, the stable credit id; `maintainedBy(card)` is `system` for a linked card and `user` otherwise, derived and never stored.

`resolveLinkedBenefit(versions, state, card, on)` builds today's `Benefit` from the household's `LinkedBenefitState` (its own id, which claims point at, enrolment, spend and the flags) and the credit's terms, so selectors, `buildSchedule` and the screens need no change:

- The version in force at the start of the current cycle supplies the terms, so a cycle already running keeps them when a new version lands.
- A credit added in a version appears from its `effectiveFrom` with that version's terms, locked if it needs enrolment.
- A credit dropped from a version ends the day before that version's `effectiveFrom`.

Catalogue storage, drafts and publishing live in the service tier (#214, #215); these are the pure rules both sides share.

## Catalogue filter

`packages/domain/lib/src/catalog_filter.dart` narrows and orders the catalogue on the add-card screen. It is Dart only, since the PWA is frozen. The blank template is never a result, because manual entry has its own buttons.

A `CatalogFilter` holds the selected fee bands, networks, card kinds, issuers and merchants, plus the search text. Its `activeCount` counts the selected values only, so the Filters badge ignores typing.

- Values in one facet are OR-ed. Facets are AND-ed with each other and with the search.
- The search is a case-insensitive substring match on issuer, product, benefit name and merchant.
- `FeeBand` splits the annual fee, in cents, into No fee (0), Under $100 (1–9,999), $100–$399 (10,000–39,999), $400–$599 (40,000–59,999) and $600+ (60,000 and up).
- `facetCounts` counts, for each option, the cards that selecting it would return. Every other facet and the search apply, but the option's own facet does not. An option stays listed at zero. The fee bands keep band order, networks and kinds keep enum order and appear only if the catalogue has them, and issuers and merchants are alphabetical.
- `sortByValue` is the only order. It puts the highest `templateAnnualValueCents` first, and ties keep catalogue order. There is no sort control.
- `matchedBenefits` names the benefits that a selected merchant or the search matched, so a row can say why it is listed.
