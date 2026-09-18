# domain

The HelpMe Reward domain rules in Dart, shared by the Flutter app and the
service tier. It is a port of the reference PWA's `apps/pwa/src/domain/`,
written against the product spec in `lat.md/product/`, with the Vitest suites
ported first so both implementations are held to the same cases.

Pure Dart, no Flutter and no packages beyond `test` and `lints` for
development. Calendar dates are `YYYY-MM-DD` strings computed in UTC; money
is whole cents.

```sh
dart pub get          # at the repository root, which is the pub workspace
dart analyze          # at the root
dart test             # in packages/domain
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

### `validation.ts` → `validation.dart`

`requiredError`, `moneyError`, `positiveMoneyError`, `anniversaryError`, `enrollmentUrlError`, `parseMoney`.

### `catalog.ts` → `catalog.dart`

`BenefitTemplate`, `CardTemplate`, `cardTemplates`, `findTemplate`, `templateAnnualValueCents`, `templateEnrollmentNames`, `benefitsFromTemplate`. The template data is generated from the TypeScript source by `apps/pwa/scripts/emit-catalog.ts`; edit there and regenerate.

## Tests

`test/` mirrors `apps/pwa/tests/` case for case for the domain suites, with the same fixtures in `factories.dart`. Each file tags the `lat.md/product/tests` section it covers with a `// @lat:` comment. `sample_household_test.dart` reads the PWA's sample household and pins the reminder group ids to the TypeScript output.
