# Tests

The product test specs: what the suites pin about dates, cycles, statuses, overlaps, reminders and form rules. They are the fastest way to see what the app believes, and the Dart port is written against them.

The reference suite is the PWA's, under `apps/pwa/tests/`, with `factories.ts` supplying fixtures so each test states only what it is about. The fixture card is an Amex Platinum held by Jim with a 14 March anniversary, and most tests are dated 16 September 2026, the same "today" as the sample household. The PWA's own suites are in [[pwa-tests]].

## Date arithmetic

`apps/pwa/tests/dates.test.ts` guards the calendar-date discipline in [[domain#Calendar dates, not timestamps]].

- Month addition clamps to the end of a shorter month and handles leap years in both directions.
- Day addition does not drift across the US DST transitions on 8 March and 1 November 2026.
- `todayIso` reads the local calendar date, not the UTC one: 23:30 local on the 16th is still the 16th.

## Cycles

`apps/pwa/tests/cycles.test.ts` covers window construction for every cadence and both anchors ([[domain#Cycle]]).

- Calendar anchors put quarters on Jan/Apr/Jul/Oct, halves on Jan/Jul, and resolve dates before the anchor year.
- Anniversary anchors run a cardmember year from the open date, place the day before the anniversary in the prior year, and do not drift for a 31st anniversary across short months.
- The invariant: consecutive cycles have no gaps and no overlaps, each starting the day after the last ends.
- Manual benefits have no window and never recur. `daysRemainingIn` is 0 on the final day and negative after. `annualValueCents` counts an untracked credit once.

## Statuses, totals and ledgers

`apps/pwa/tests/selectors.test.ts` pins the status ladder and the derived views ([[domain#Status ladder]], [[domain#Missed ledger]]).

- Every rung: use soon inside 30 days, available beyond, captured when fully claimed (even while locked), partial claims summed, locked before enrolment and unlocked after, manual never at risk, archived cards and inactive credits skipped.
- Ordering puts what closes soonest first and locked below open.
- The four totals stay apart. `nextReset` reports the nearest open window.
- Overlaps: one credit on two cards is flagged with `sameProduct`; different issuers match by merchant; two credits on the same card do not overlap; the group totals what is still unclaimed.
- The missed ledger counts closed windows with nothing claimed, counts only the shortfall for partial use, never blames windows before tracking began, and ignores manual credits. Leaks group repeats and rank by money lost. Monthly totals bin claims by when logged and misses by when the window shut.
- `summarizeCard` reports net against the fee; `cardLabel` names the holder and prefers a nickname.

## Ladder and schedule

`apps/pwa/tests/reminders.test.ts` covers when a notification fires and what it says ([[reminders#The ladder]], [[reminders#Schedule construction]]).

- Each cadence's rungs match the table, open permissive and end urgent, and collapse to one last call when opted out. `currentRung` reports the rung a credit stands on.
- The schedule is empty while reminders are off, fires a rung at the reminder time on the right day, never schedules in the past, and returns reminders in firing order.
- Same-day credits group into one notification led by the biggest loss; a mostly-locked group leads with the blocker; locked credits are silent when enrolment reminders are off.
- Muted credits, muted cards, fully claimed cycles, manual credits and sub-floor values are skipped; a partly used credit is reminded about for its balance.
- Ids are stable and unique across recomputes, so the delivery layer's dedupe holds.
- `dueReminders` returns only what has come due and not been shown, and drops anything the device slept through for days.

## Form rules

`apps/pwa/tests/validation.test.ts` covers each rule in [[domain#Form rules]] without the DOM.

### A required field must not be blank

Blank and whitespace-only values return the caller's sentence; any text returns null.

### Money must be a number, and a value must be above zero

Empty, non-numeric and negative amounts fail the money rule; zero passes it. The positive rule also fails zero and passes a cent.

### An anniversary must be a calendar date

Empty, impossible (month 13) and non-ISO dates fail; an ISO date passes.

### An enrolment page must be a web address

Nothing given passes; a bare domain or an ftp scheme fails; http and https pass.
