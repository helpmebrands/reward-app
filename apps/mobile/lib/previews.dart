import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/widget_previews.dart';

import 'data/snapshot_store.dart';
import 'logic/app_store.dart';
import 'main.dart';
import 'screens/stub_screen.dart';
import 'screens/today_screen.dart';
import 'theme/theme.dart';
import 'widgets/credit_row.dart';

/// Widget previews for every UI component, on a small household so the
/// screens render populated rather than empty.

const _today = '2026-09-16';

Card _card(String id, String holder) => Card(
  id: id,
  issuer: 'American Express',
  product: 'Platinum',
  holder: holder,
  network: CardNetwork.amex,
  annualFeeCents: 89500,
  anniversaryOn: '2021-03-14',
  muted: false,
  archived: false,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

Benefit _benefit(
  String id,
  String cardId,
  String name,
  int valueCents, {
  Cadence cadence = Cadence.monthly,
  bool enrollmentRequired = false,
  String? merchant,
}) => Benefit(
  id: id,
  cardId: cardId,
  name: name,
  category: BenefitCategory.other,
  merchant: merchant,
  valueCents: valueCents,
  cadence: cadence,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: enrollmentRequired,
  redemptionSteps: const [],
  muted: false,
  lastCallOnly: false,
  active: true,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

AppData _household() => AppData(
  version: 1,
  cards: [_card('jim', 'Jim'), _card('kathy', 'Kathy')],
  benefits: [
    _benefit('u1', 'jim', 'Uber Cash', 1500, merchant: 'Uber'),
    _benefit('u2', 'kathy', 'Uber Cash', 1500, merchant: 'Uber'),
    _benefit(
      'r1',
      'kathy',
      'Resy Dining Credit',
      10000,
      cadence: Cadence.quarterly,
    ),
    _benefit(
      'e1',
      'kathy',
      'Equinox Credit',
      30000,
      cadence: Cadence.annual,
      enrollmentRequired: true,
    ),
  ],
  claims: const [
    Claim(
      id: 'c1',
      benefitId: 'u1',
      cycleKey: '2026-09-01',
      amountCents: 1500,
      claimedAt: '2026-09-10T12:00:00.000Z',
    ),
  ],
  settings: const Settings(
    notifications: NotificationSettings(
      enabled: false,
      timeOfDay: '09:00',
      minValueCents: 100,
      annualFeeReminder: true,
      enrollmentReminder: true,
    ),
    useSoonDays: 30,
    theme: ThemeSetting.system,
    holderFilter: '',
  ),
);

AppStore _store() {
  final store = AppStore(
    store: MemorySnapshotStore(_household()),
    clock: () => _today,
  );
  store.load();
  return store;
}

Widget _themed(Widget child, Brightness brightness) => MaterialApp(
  theme: nocturneTheme(brightness),
  home: Scaffold(body: SafeArea(child: child)),
);

@Preview(name: 'Today, dark', size: Size(402, 874))
Widget todayDark() => _themed(TodayScreen(store: _store()), Brightness.dark);

@Preview(name: 'Today, light', size: Size(402, 874))
Widget todayLight() => _themed(TodayScreen(store: _store()), Brightness.light);

@Preview(name: 'Shell, compact', size: Size(402, 874))
Widget shellCompact() => RewardApp(store: _store());

@Preview(name: 'Shell, medium', size: Size(768, 1024))
Widget shellMedium() => RewardApp(store: _store());

@Preview(name: 'Shell, expanded', size: Size(1280, 800))
Widget shellExpanded() => RewardApp(store: _store());

@Preview(name: 'Placeholder screen', size: Size(402, 300))
Widget stubScreen() => _themed(const StubScreen('Cards'), Brightness.dark);

@Preview(name: 'Credit rows, every tone', size: Size(402, 400))
Widget creditRows() {
  final instances = currentInstances(_household(), _today);
  return _themed(
    ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final instance in instances)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CreditRow(instance: instance, showCard: true),
          ),
      ],
    ),
    Brightness.dark,
  );
}
