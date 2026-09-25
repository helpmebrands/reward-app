# domain

The HelpMe Reward domain rules in Dart, shared by the Flutter app and the
service tier. It is a port of the retired PWA's TypeScript domain (#174),
written against the product spec in `lat.md/product/`, with the Vitest suites
ported first so both implementations were held to the same cases.

Pure Dart, no Flutter and no packages beyond `test` and `lints` for
development. Calendar dates are `YYYY-MM-DD` strings computed in UTC; money
is whole cents.

```sh
fvm dart pub get      # at the repository root, which is the pub workspace
fvm dart analyze      # at the root
fvm dart test         # in packages/domain
```

## Every export, and its Dart equivalent

One file per TypeScript module. Names are the same except where Dart style
requires otherwise: enum members are `lowerCamelCase` (`use_soon` is
`BenefitStatus.useSoon`, `fee_credit` is `BenefitCategory.feeCredit`), the
`USE_SOON_DAYS` constant is `useSoonDays`, and `CARD_TEMPLATES` is
`cardTemplates`. Optional trailing arguments become optional positional or
named parameters as noted.

### `types.ts` → `types.dart`

| TypeScript | Dart |
| --- | --- |
| `IsoDate`, `IsoInstant`, `Uuid` | `typedef`s over `String` |
| `Cadence`, `CycleAnchor`, `BenefitCategory`, `CardNetwork`, `BenefitStatus` | enums |
| `LadderRung['tone']`, `Settings['theme']` | `Tone`, `ThemeSetting` enums |
| `Card`, `Benefit`, `Cycle`, `Claim`, `BenefitInstance`, `LadderRung`, `NotificationSettings`, `Settings`, `AppData` | immutable classes with named constructors; `Cycle` has value equality |
| `USE_SOON_DAYS` | `useSoonDays` |

### `dates.ts` → `dates.dart`

`DateParts`, `parseIsoDate`, `formatIsoDate`, `daysInMonth`, `addDays`, `addMonths`, `daysBetween`, `compareIsoDate`, `minIsoDate`, `maxIsoDate`, `isWithin`, `todayIso([DateTime? now])`, `startOfDayLocal`, `atLocalTime`.

### `cycles.ts` → `cycles.dart`

`monthsPerCycle`, `anchorDateFor`, `cycleLabel`, `cycleFor`, `nextCycle`, `previousCycle`, `cyclesBetween(…, {maxCycles})`, `closedCyclesBefore`, `isCycleOpen`, `daysRemainingIn`, `cycleProgress`, `cadenceLabel`, `annualValueCents`.

### `selectors.ts` → `selectors.dart`

`ClaimIndex`, `indexClaims`, `claimedIn`, `isLocked`, `resolveInstance(…, {useSoonHorizon})`, `currentInstances([on])`, `compareByUrgency`, `isClaimable`, `byStatus`, `sumRemaining`, `sumClaimed`, `Totals`, `totalsFor`, `useSoon`, `nextReset`, `OverlapGroup`, `findOverlaps`, `MissedCycle`, `missedCycles([on, lookbackCycles])`, `Leak`, `biggestLeaks({limit})`, `MonthTotals`, `monthlyTotals({on, months})`, `CardSummary`, `summarizeCard([on])`, `cardYearStart`, `claimedThisCardYear`, `daysUntilRenewal`, `holders`, `cardLabel`, `categoryLabel`, `statusLabel`.

### `ladder.ts` → `ladder.dart`

`ladderFor`, `defaultLadder`, `ladderSummary`, `currentRung`.

### `reminders.ts` → `reminders.dart`

`ReminderItem`, `Reminder`, `ReminderSchedule`, `buildSchedule([now, horizon])`, `dueReminders(…, {graceMs})`. `fireAt` and `generatedAt` are epoch milliseconds, as in the PWA.

### `format.ts` → `format.dart`

`formatMoney`, `formatMoneyExact`, `parseMoneyToCents`, `formatDate`, `formatRange`, `formatDaysRemaining`, `describeDeadline`, `formatRelativeFromToday`, `initials`, `formatHeaderDate`, `formatResetDate`, `moneyParts` (a record `({String symbol, String digits})`). Money is US dollars and dates use the forms the screens were drawn with, hand-rolled rather than read from a locale table.

### The snapshot JSON (`json.dart`, Dart only)

`appDataFromJson`, `appDataToJson` and the per-type `cardFromJson`, `cardToJson`, `benefitFromJson`, `benefitToJson`, `claimFromJson`, `claimToJson`, `settingsFromJson`, `settingsToJson`, plus `statusFromJson` and `statusToJson`. The PWA's snapshot is plain JSON of its TypeScript objects, so it needs no codec; this one reads and writes that exact shape, `snake_case` enum spellings and omitted optionals included, so a household moves between the apps unchanged.

### `validation.ts` → `validation.dart`

`requiredError`, `moneyError`, `positiveMoneyError`, `anniversaryError`, `enrollmentUrlError`, `parseMoney`.

### `catalog.ts` → `catalog.dart`

`BenefitTemplate`, `CardTemplate`, `cardTemplates`, `findTemplate`, `templateAnnualValueCents`, `templateEnrollmentNames`, `benefitsFromTemplate`. The template data was first generated from the PWA's catalogue and is now edited by hand here; `services/api` seeds its catalogue from it.

## Tests

`test/` carries the retired PWA's domain suites case for case, with the same fixtures in `factories.dart`. Each file tags the `lat.md/product/tests` section it covers with a `// @lat:` comment. `test/fixtures/sample-household.json` is the sample household the Flutter tests also read; `sample_household_test.dart` pins its reminder group ids to the TypeScript output.
