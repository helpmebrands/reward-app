# Tests

The product test specs: what the suites pin about dates, cycles, statuses, overlaps, reminders and form rules. They are the fastest way to see what the app believes, and the Dart port is written against them.

The reference suite is the PWA's, under `apps/pwa/tests/`, with `factories.ts` supplying fixtures so each test states only what it is about. The Dart port in `packages/domain/test/` carries the same cases, one file per file, with the same fixtures in `factories.dart`; each Dart file tags the section it covers. The fixture card is an Amex Platinum held by Jim with a 14 March anniversary, and most tests are dated 16 September 2026, the same "today" as the sample household. The PWA's own suites are in [[pwa-tests]].

## Date arithmetic

`apps/pwa/tests/dates.test.ts` and its port `packages/domain/test/dates_test.dart` guard the calendar-date discipline in [[domain#Calendar dates, not timestamps]].

- Month addition clamps to the end of a shorter month and handles leap years in both directions.
- Day addition does not drift across the US DST transitions on 8 March and 1 November 2026.
- `todayIso` reads the local calendar date, not the UTC one: 23:30 local on the 16th is still the 16th.

## Cycles

`apps/pwa/tests/cycles.test.ts` and its port `packages/domain/test/cycles_test.dart` cover window construction for every cadence and both anchors ([[domain#Cycle]]).

- Calendar anchors put quarters on Jan/Apr/Jul/Oct, halves on Jan/Jul, and resolve dates before the anchor year.
- Anniversary anchors run a cardmember year from the open date, place the day before the anniversary in the prior year, and do not drift for a 31st anniversary across short months.
- The invariant: consecutive cycles have no gaps and no overlaps, each starting the day after the last ends.
- Manual benefits have no window and never recur. `daysRemainingIn` is 0 on the final day and negative after. `annualValueCents` counts an untracked credit once.

## Statuses, totals and ledgers

`apps/pwa/tests/selectors.test.ts` and its port `packages/domain/test/selectors_test.dart` pin the status ladder and the derived views ([[domain#Status ladder]], [[domain#Missed ledger]]).

- Every rung: use soon inside 30 days, available beyond, captured when fully claimed (even while locked), partial claims summed, locked before enrolment and unlocked after, manual never at risk, archived cards and inactive credits skipped.
- Ordering puts what closes soonest first and locked below open.
- The four totals stay apart. `nextReset` reports the nearest open window.
- Overlaps: one credit on two cards is flagged with `sameProduct`; different issuers match by merchant; two credits on the same card do not overlap; the group totals what is still unclaimed.
- The missed ledger counts closed windows with nothing claimed, counts only the shortfall for partial use, never blames windows before tracking began, and ignores manual credits. Leaks group repeats and rank by money lost. Monthly totals bin claims by when logged and misses by when the window shut.
- `summarizeCard` reports net against the fee; `cardLabel` names the holder and prefers a nickname.

## Ladder and schedule

`apps/pwa/tests/reminders.test.ts` and its port `packages/domain/test/reminders_test.dart` cover when a notification fires and what it says ([[reminders#The ladder]], [[reminders#Schedule construction]]).

- Each cadence's rungs match the table, open permissive and end urgent, and collapse to one last call when opted out. `currentRung` reports the rung a credit stands on.
- The schedule is empty while reminders are off, fires a rung at the reminder time on the right day, never schedules in the past, and returns reminders in firing order.
- Same-day credits group into one notification led by the biggest loss; a mostly-locked group leads with the blocker; locked credits are silent when enrolment reminders are off.
- Muted credits, muted cards, fully claimed cycles, manual credits and sub-floor values are skipped; a partly used credit is reminded about for its balance.
- Ids are stable and unique across recomputes, so the delivery layer's dedupe holds.
- `dueReminders` returns only what has come due and not been shown, and drops anything the device slept through for days.

### The sample household schedules the same ids in Dart

`packages/domain/test/sample_household_test.dart` builds the schedule for the PWA's sample household on 16 September 2026 and expects the group ids the TypeScript build produces.

The expected list is `test/fixtures/sample-schedule-ids.json`, dumped by `apps/pwa/scripts/schedule-ids.ts`. A drift here means the two implementations would remind on different days.

## Form rules

`apps/pwa/tests/validation.test.ts` and its port `packages/domain/test/validation_test.dart` cover each rule in [[domain#Form rules]] without the DOM.

### A required field must not be blank

Blank and whitespace-only values return the caller's sentence; any text returns null.

### Money must be a number, and a value must be above zero

Empty, non-numeric and negative amounts fail the money rule; zero passes it. The positive rule also fails zero and passes a cent.

### An anniversary must be a calendar date

Empty, impossible (month 13) and non-ISO dates fail; an ISO date passes.

### An enrolment page must be a web address

Nothing given passes; a bare domain or an ftp scheme fails; http and https pass.

## Snapshot JSON

`packages/domain/test/json_test.dart` pins the codec for the persisted snapshot, which the Flutter store and any export share with the PWA's stored record and export file.

### The sample household round-trips unchanged

The PWA's sample household decodes to two cards, twenty-four benefits and twenty claims, and encodes back to JSON equal to the file, so nothing is dropped or renamed in either direction.

### Enums use the PWA's spellings

`fee_credit` and `use_soon` decode to `BenefitCategory.feeCredit` and `BenefitStatus.useSoon` and encode back to the same strings; absent optionals decode to null and are omitted on encode, and a missing `redemptionSteps` reads as empty.

## Card catalogue

`packages/domain/test/catalog_test.dart` pins the starting templates in [[domain#Card catalogue]]. The PWA covers the first case from its store suite; the rest are Dart-only, since the PWA exercised them through the add-card screen.

### Every template gives each credit an icon and a value

Every credit in every template has an icon name and a value above zero, so a template can never land a blank row on Today.

### Templates are found by id and end with blank

`findTemplate` returns the template for a known id and null otherwise, and the last template is `blank`, the empty one the add-card flow offers for cards the catalogue does not know.

### A template prices its year and names its locked credits

`templateAnnualValueCents` multiplies each credit by its cadence's cycles per year, counting manual once, and `templateEnrollmentNames` lists the credits behind an enrolment box.

### Template credits become ordinary benefits

`benefitsFromTemplate` stamps every entry into a benefit with a fresh id, the new card's id, the given timestamps, active and unmuted, keeping `enrollmentRequired` so the credit lands locked or spendable as the template says.

## Formatting

`packages/domain/test/format_test.dart` pins the display forms in `format.dart`. The PWA's equivalents are locale-driven `Intl` calls exercised only through components; the port hand-rolls them, so these specs are what the two must agree on.

### Whole dollars drop the cents

`$15` for 1500 cents, `$12.95` for 1295, thousands grouped as `$1,500`, a negative as `-$5`; `formatMoneyExact` always shows cents, and `moneyParts` splits the symbol from the digits.

### Typed money becomes whole cents

`parseMoneyToCents` strips currency symbols and commas before parsing and refuses blanks, words and negatives; `parseMoney` (the form rule) accepts a sign, rejects commas and rounds to whole cents.

### Dates show the year only outside the current one

`formatDate` gives `Sep 30` inside the current year and `Mar 13, 2027` outside it; `formatRange` joins two with an en dash; the header reads `Tue, 15 Sep` and a reset date `30 September`.

### Deadlines read the way a person would say them

Negative days are `Expired`, then `Today`, `Tomorrow`, whole days under a week, weeks under a month, months under a year, and years after that, rounded the way `format.ts` rounds them.

### Screen readers hear the date with the deadline

`describeDeadline` says `Expires today`, `Expires tomorrow`, `Expires in N days` or `Expired on`, each followed by the formatted date.

### Initials come from the first two words

`initials` takes the first letter of the first two words, the first two letters of a single word, and `?` for nothing.

