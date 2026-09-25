# Tests

The product test specs: what the suites pin about dates, cycles, statuses, overlaps, reminders and form rules. They are the fastest way to see what the app believes, and the Dart port is written against them.

The suite is `packages/domain/test/`, ported case for case from the retired PWA's (#174), with `factories.dart` supplying fixtures so each test states only what it is about; each file tags the section it covers. The fixture card is an Amex Platinum held by Jim with a 14 March anniversary, and most tests are dated 16 September 2026, the same "today" as the sample household in `test/fixtures/sample-household.json`.

## Date arithmetic

`packages/domain/test/dates_test.dart` guard the calendar-date discipline in [[domain#Calendar dates, not timestamps]].

- Month addition clamps to the end of a shorter month and handles leap years in both directions.
- Day addition does not drift across the US DST transitions on 8 March and 1 November 2026.
- `todayIso` reads the local calendar date, not the UTC one: 23:30 local on the 16th is still the 16th.

## Cycles

`packages/domain/test/cycles_test.dart` cover window construction for every cadence and both anchors ([[domain#Cycle]]).

- Calendar anchors put quarters on Jan/Apr/Jul/Oct, halves on Jan/Jul, and resolve dates before the anchor year.
- Anniversary anchors run a cardmember year from the open date, place the day before the anniversary in the prior year, and do not drift for a 31st anniversary across short months.
- The invariant: consecutive cycles have no gaps and no overlaps, each starting the day after the last ends.
- Manual benefits have no window and never recur. `daysRemainingIn` is 0 on the final day and negative after. `annualValueCents` counts an untracked credit once.
- A credit with `endsOn` clamps its final window to that day, has no window after it, still lists the final window among the closed ones once it has passed, and keeps its unprorated annual value.
- A rolling credit is eligible now with no deadline and no next cycle until claimed; a claim closes a window from the claim day for `intervalMonths` and the next opens the day after; its annual value is amortised.

## Statuses, totals and ledgers

`packages/domain/test/selectors_test.dart` pin the status ladder and the derived views ([[domain#Status ladder]], [[domain#Missed ledger]]).

- Every rung: use soon inside 30 days, available beyond, captured when fully claimed (even while locked), partial claims summed, locked before enrolment and unlocked after, manual never at risk, archived cards and inactive credits skipped.
- Ordering puts what closes soonest first and locked below open.
- The four totals stay apart. `nextReset` reports the nearest open window.
- Overlaps: one credit on two cards is flagged with `sameProduct`; different issuers match by merchant; two credits on the same card do not overlap; the group totals what is still unclaimed.
- The missed ledger counts closed windows with nothing claimed, counts only the shortfall for partial use, never blames windows before tracking began, and ignores manual credits. Leaks group repeats and rank by money lost. Monthly totals bin claims by when logged and misses by when the window shut.
- `summarizeCard` reports net against the fee; `cardLabel` names the holder and prefers a nickname.
- A credit with `endsOn` goes Use soon against the clamped end, is absent the day after it ends, and leaves its final shortfall in the missed ledger.
- A spend-gated credit is locked for `spend` until `spendMetAt` falls in the current year (calendar or cardmember, by anchor), enrolment is named first when both apply, and `summarizeCard` counts nothing for it while gated.
- A rolling credit is Available until claimed, Captured until its interval ends, Available again under a new key, never Use soon or missed even with a partial claim, and worth its amortised value on the card.

## Opted-out credits

`packages/domain/test/opted_out_test.dart` pins credits the household will never use ([[domain#Status ladder#Opted out is a choice, not a status of the window]]).

### Opted out outranks every other rung

A credit with `optedOutAt` is `optedOut` even when fully claimed or locked, and is never claimable. `statusLabel` calls it "Opted out".

### Opted out is its own total

`totalsFor` puts the annual value of opted-out credits in `optedOutCents`, and leaves them out of claimable, locked and captured, even with a claim logged this cycle.

### Opted out is never missed

A credit opted out all year adds nothing to the missed ledger.

### Opted out is never reminded

`buildSchedule` produces no reminder for an opted-out credit.

### Windows closed before tracking resumed are not missed

With `trackedFrom` set, `missedCycles` skips every window that closed before that day, so reactivating a credit never counts the gap as missed.

### A card has a potential and a usable value

`summarizeCard` reports `potentialValueCents` with opted-out credits included and spend-gated ones left out, `annualValueCents` without either, and `optedOutCents` for the difference.

### Opted out and tracked from round-trip

`optedOutAt` and `trackedFrom` survive the codec and are omitted when absent.

### A paused credit loads as opted out

A legacy `active: false` credit that had not ended by its `updatedAt` loads active and opted out at that instant; one whose `endsOn` had passed stays inactive.

### A linked credit carries its opt-out

`benefitFromCredit` copies `optedOutAt` and `trackedFrom` from the household's `LinkedBenefitState`.

## Ladder and schedule

`packages/domain/test/reminders_test.dart` cover when a notification fires and what it says ([[reminders#The ladder]], [[reminders#Schedule construction]]).

- Each cadence's rungs match the table, open permissive and end urgent, and collapse to one last call when opted out. `currentRung` reports the rung a credit stands on.
- The schedule is empty while reminders are off, fires a rung at the reminder time on the right day, never schedules in the past, and returns reminders in firing order.
- Same-day credits group into one notification led by the biggest loss; a mostly-locked group leads with the blocker; locked credits are silent when enrolment reminders are off.
- Muted credits, muted cards, fully claimed cycles, manual credits and sub-floor values are skipped; a partly used credit is reminded about for its balance.
- A credit that ends on a date is reminded against the clamped end and never after it.
- A spend-locked credit is never scheduled, even with enrolment reminders on.
- A rolling credit has one unscheduled rung and is never scheduled.
- Ids are stable and unique across recomputes, so the delivery layer's dedupe holds.
- `dueReminders` returns only what has come due and not been shown, and drops anything the device slept through for days.

### The sample household schedules the same ids in Dart

`packages/domain/test/sample_household_test.dart` builds the schedule for the PWA's sample household on 16 September 2026 and expects the group ids the TypeScript build produces.

The expected list is `test/fixtures/sample-schedule-ids.json`, dumped once by the retired PWA (#174). A drift here means the Dart schedule has left the reference it was ported against.

## Form rules

`packages/domain/test/validation_test.dart` cover each rule in [[domain#Form rules]] without the DOM.

### A required field must not be blank

Blank and whitespace-only values return the caller's sentence; any text returns null.

### Money must be a number, and a value must be above zero

Empty, non-numeric and negative amounts fail the money rule; zero passes it. The positive rule also fails zero and passes a cent.

### An anniversary must be a calendar date

Empty, impossible (month 13) and non-ISO dates fail; an ISO date passes.

### A rolling credit needs whole months between claims

Blank, zero, a fraction and a word all fail for `rolling`; a whole number passes; any value passes for another cadence, which has no interval.

### An end date is optional but must be a calendar date

Blank and whitespace-only pass, since most credits have no end; an impossible (month 13) or non-ISO date fails; an ISO date passes.

### An enrolment page must be a web address

Nothing given passes; a bare domain or an ftp scheme fails; http and https pass.

## Card labels

`selectors_test.dart`, `reminders_test.dart` and `json_test.dart` pin the display name that replaced the holder ([[domain#Card]]).

### A card shows its label or its product name

A card without a label, or with a blank one, shows "American Express Platinum"; one labelled "The travel one" shows that.

### A duplicate product proposes a numbered label

With no Platinum there is nothing to propose; after one it proposes "American Express Platinum (1)", after that "(2)"; another product proposes nothing.

### Deleting a card renames nothing

Of three identical cards, removing the unlabelled first leaves "(1)" and "(2)" as they were, and a fourth card needs no number because the product name is free again.

### A label may not repeat another card's display name

A label equal to another card's display name, in any case and with spaces around it, is refused with a sentence naming it.

A card's own label, a fresh one, and a blank label on a product nobody else shows pass; a blank label on a product another card shows is refused.

### Notification copy names the card by its display name

A single-credit reminder on a card labelled "Travel card" reads "Uber Cash at Uber on Travel card. $15 untouched."

### A label round-trips and is omitted when absent

`label` reads and writes under its own key, and a card without one writes no key.

## Member preferences

`reminders_test.dart`, `selectors_test.dart` and `json_test.dart` pin the split of reminder settings and mutes from the household ([[domain#Member preferences]]).

### Two members of one household get their own schedules

Two cards with a monthly credit each; the member with nothing muted is reminded about both, the member who muted the first card only about the second.

### Mutes come from the member, not the household

Without preferences no instance is muted; a benefit mute marks only that credit, and a card mute marks every credit on the card.

### Member preferences round-trip

Every field reads back as written, and the muted ids write as sorted lists so the same preferences always give the same JSON.

## Catalogue versions

`catalog_versions_test.dart` pins the versioned catalogue ([[domain#Catalogue versions]]) with a two-version Platinum: version 2 from 15 October 2026 raises Uber from $15 to $20, drops Resy and adds a locked Equinox credit.

### Every template credit has a stable id

Every credit in `cardTemplates` has an id under its template's, in lower-case kebab slugs and unique within the template; `amex-gold/uber-cash` finds the Gold's Uber Cash.

### The version in force is the latest that has started

Nothing is in force before version 1; version 1 applies the day before version 2's date and version 2 from it, in either list order.

### A cycle resolves against the version in force at its start

On 20 October the Uber cycle began on the 1st, under version 1, so it is still $15; on 5 November it is $20 and names its stable credit id.

### Claims attach across versions by the stable id

October's and November's resolved Uber benefits share the household's id, so a claim logged against that id counts in November's cycle.

### A credit dropped from a version stops at its effectiveFrom

Resy resolved on 20 October ends on 14 October and has ended; in September it has no end.

### A credit added in a version appears from its effectiveFrom

Equinox does not exist on 14 October; on 20 October it is $25 and locked behind enrolment.

### A template link makes a card system-maintained

A card without `templateId` is maintained by the user, one with it by the system.

### Templates and versions round-trip as JSON

Every catalogue template, as a version, writes `id`, `version`, `effectiveFrom`, the template's fields and its credits, and reads back to the same JSON; an absent `endsOn` is left out. This is the service tier's wire format for the catalogue.

### The links round-trip in the snapshot

`templateId` and `templateBenefitId` read back as written, and are left out when absent.

## Snapshot JSON

`packages/domain/test/json_test.dart` pins the codec for the persisted snapshot, which the Flutter store and any export share with the PWA's stored record and export file.

### The sample household round-trips unchanged

The PWA's sample household decodes to two cards, twenty-four benefits and twenty claims, and encodes back to JSON equal to the file, so nothing is dropped or renamed in either direction.

### A card without a kind loads as personal

A card record with no `kind` decodes as `CardKind.personal` and encodes `kind: personal`; `business` round-trips and `copyWith` can change it, so a snapshot from before the field existed loads with every card personal.

### The sample household rolls its Global Entry credits

The sample's two Global Entry credits are `rolling` with `intervalMonths` 48 and nothing in it is `manual`, so the fixtures dumped from it exercise the rolling window.

### Enums use the PWA's spellings

`fee_credit` and `use_soon` decode to `BenefitCategory.feeCredit` and `BenefitStatus.useSoon` and encode back to the same strings; absent optionals decode to null and are omitted on encode, and a missing `redemptionSteps` reads as empty.

### An end date round-trips and is omitted when absent

`endsOn` decodes to the same string and encodes back to it; clearing it through `copyWith` drops the key on encode, so an open-ended credit writes no `endsOn`.

### A rolling cadence round-trips with its interval

`cadence: rolling` and `intervalMonths` decode to the enum and the number and encode back; clearing the interval through `copyWith` drops the key.

### A spend threshold round-trips with its met stamp

`spendThresholdCents` and `spendMetAt` decode to the same values and encode back; clearing both through `copyWith` drops both keys, so an ungated credit writes neither.

## Card catalogue

`packages/domain/test/catalog_test.dart` pins the starting templates in [[domain#Card catalogue]].

### Every template gives each credit an icon and a value

Every credit in every template has an icon name and a value above zero, so a template can never land a blank row on Today.

### Templates are found by id and end with blank

`findTemplate` returns the template for a known id and null otherwise, and the last template is `blank`, the empty one the add-card flow offers for cards the catalogue does not know.

### A template prices its year and names its locked credits

`templateAnnualValueCents` multiplies each credit by its cadence's cycles per year, counting manual once, and `templateEnrollmentNames` lists the credits behind an enrolment box.

### Business Platinum is priced at its unconditional credits

The shipped `amex-business-platinum` template gates the Dell $5K bonus and the two $250K credits, and `templateAnnualValueCents` equals the sum of the rest, well under four times the fee. Covered in both languages.

### Every Global Entry credit rolls every 48 months

Every shipped credit named "Global Entry…" is `rolling` with `intervalMonths` 48 and amortises to $30 a year, and no shipped credit is `manual` any more. Covered in both languages.

### Dated credits carry their end

The Sapphire Reserve's StubHub, Peloton and two DoorDash credits end on 2027-12-31 and its Lyft credit on 2027-09-30; the United Quest's two Instacart credits end on 2027-12-31. Covered in both languages.

### Every template names its kind

The Business Platinum template is `business`, the blank one `personal`, and every template carries one of the two. Covered in both languages.

### The IHG spend credit is gated

The IHG Premier's "$20K Spend Statement Credit" carries a $20,000 threshold. Covered in both languages.

### A template amortises a rolling credit

A $120 credit every 48 months beside a $15 monthly one prices at $210 a year, and `benefitsFromTemplate` carries the cadence and the interval onto the benefit. Covered in both languages.

### A template prices its year without its spend-gated credits

A template with a $1,200 annual credit behind $250K of spend and a $15 monthly one is worth $180 a year, and `benefitsFromTemplate` carries the threshold onto the benefit. Covered in both languages.

### Template credits become ordinary benefits

`benefitsFromTemplate` stamps every entry into a benefit with a fresh id, the new card's id, the given timestamps, active and unmuted, keeping `enrollmentRequired` so the credit lands locked or spendable as the template says.

### A template credit that has already ended lands inactive

`benefitsFromTemplate` copies `endsOn`; an entry whose date is before the day the card is added lands `active: false`, one still ahead lands active, and one without a date is unchanged.

The PWA's `catalog.test.ts` stamped the same synthetic template before it was retired.

## Catalogue filter

`packages/domain/test/catalog_filter_test.dart` pins [[domain#Catalogue filter]]. Dart only. The cases use synthetic templates for the semantics and the shipped catalogue for the counts.

### Fee bands split at their cent boundaries

0 is No fee, 1 and 9,999 are Under $100, 10,000 and 39,999 are $100–$399, 40,000 and 59,999 are $400–$599, and 60,000 is $600+. The labels are fixed.

### Values OR within a facet and facets AND together

Two selected issuers return their union, adding a merchant intersects that union, a network no card has returns nothing, and results keep the given order.

### Search matches issuer, product, benefit name and merchant

"UbEr" matches cards only through a benefit name or merchant, including the Platinum. "chase" matches through the issuer, and "sapphire p" matches only the Sapphire Preferred.

### The blank template never appears

Neither `filterTemplates` nor `facetCounts` returns `blank`, so no empty issuer, no "other" network and no zero-fee card is counted.

### A facet's counts ignore its own selection

With Chase selected, the issuer counts equal the unfiltered ones (Chase is 4). Each merchant count equals the number of Chase cards carrying that merchant, and the fee band counts add up to 4.

### Options stay listed at zero and follow a fixed order

With Wells Fargo selected, all five fee bands are listed and $600+ reads 0. Networks are Amex, Visa and Mastercard, with Amex at 0. The six issuers are alphabetical. The merchants are unique and alphabetical ignoring case, and Uber reads 0.

### The kind facet ORs its kinds and counts past its own selection

Business alone returns only the Business Platinum, and Business plus Personal returns every card. The kind counts stay 15 personal and 1 business with Business selected, and fall to 4 and 0 once Chase is also selected.

A catalogue with no business template does not offer the Business option.

### The catalogue sorts by annual value, ties in catalogue order

`sortByValue` puts the highest `templateAnnualValueCents` first and keeps equal values in their given order, for both synthetic templates and the shipped catalogue.

### The active count leaves out the search text

An empty filter is empty with a count of 0. Two selected values plus search text count 2, toggling one off counts 1, and search text alone makes the filter non-empty.

### Matched benefits come from the merchant or the search

With no merchant and no search, the Platinum has no matched benefits. With Uber selected it has only Uber benefits, "resy" matches only its Resy credits, and "platinum" matches the card but none of its benefits.

## Formatting

`packages/domain/test/format_test.dart` pins the display forms in `format.dart`. The PWA's equivalents are locale-driven `Intl` calls exercised only through components; the port hand-rolls them, so these specs are what the two must agree on.

### Whole dollars drop the cents

`$15` for 1500 cents, `$12.95` for 1295, thousands grouped as `$1,500`, a negative as `-$5`; `formatMoneyExact` always shows cents, and `moneyParts` splits the symbol from the digits.

### Typed money becomes whole cents

`parseMoneyToCents` strips currency symbols and commas before parsing and refuses blanks, words and negatives; `parseMoney` (the form rule) accepts a sign, rejects commas and rounds to whole cents.

### A credit's value reads with its cadence

`formatValuePerCycle` gives "$15/mo", "$50/qtr", "$300/half", "$200/yr" and "$12.95/mo". A rolling credit reads "$120/48 mo", and a manual one is the bare "$50". Dart only; the catalogue's matched-credit tags use it.

### Dates show the year only outside the current one

`formatDate` gives `Sep 30` inside the current year and `Mar 13, 2027` outside it; `formatRange` joins two with an en dash; the header reads `Tue, 15 Sep` and a reset date `30 September`.

### Deadlines read the way a person would say them

Negative days are `Expired`, then `Today`, `Tomorrow`, whole days under a week, weeks under a month, months under a year, and years after that, rounded the way `format.ts` rounds them.

### Screen readers hear the date with the deadline

`describeDeadline` says `Expires today`, `Expires tomorrow`, `Expires in N days` or `Expired on`, each followed by the formatted date.

### Initials come from the first two words

`initials` takes the first letter of the first two words, the first two letters of a single word, and `?` for nothing.

