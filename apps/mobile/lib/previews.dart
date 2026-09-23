import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/widget_previews.dart';

import 'data/snapshot_store.dart';
import 'logic/app_store.dart';
import 'logic/credit_actions.dart';
import 'logic/snackbar_state.dart';
import 'logic/ui_state.dart';
import 'main.dart';
import 'screens/add_card_screen.dart';
import 'screens/benefit_editor_screen.dart';
import 'screens/card_editor_screen.dart';
import 'screens/cards_screen.dart';
import 'screens/credits_screen.dart';
import 'screens/stub_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/today_screen.dart';
import 'screens/value_screen.dart';
import 'shell/width_class.dart';
import 'theme/theme.dart';
import 'widgets/credit_row.dart';
import 'widgets/compare_sheet.dart';
import 'widgets/credit_sheet.dart';
import 'widgets/field.dart';
import 'widgets/holder_filter.dart';
import 'widgets/nudge_preview.dart';
import 'widgets/sheet_host.dart';
import 'widgets/snackbar_host.dart';

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
    Claim(
      id: 'c2',
      benefitId: 'r1',
      cycleKey: '2026-07-01',
      amountCents: 1000,
      claimedAt: '2026-09-02T12:00:00.000Z',
      note: 'Lunch',
    ),
    Claim(
      id: 'c3',
      benefitId: 'r1',
      cycleKey: '2026-07-01',
      amountCents: 2000,
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
    clock: () => DateTime(2026, 9, 16),
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

/// Rows with their actions wired to the store: swipe right to log, left
/// to silence, tap the bell, or tap the row; the snackbar shows the undo.
@Preview(name: 'Credit rows, swipe to act', size: Size(402, 500))
Widget creditRowsSwipe() {
  final store = _store();
  final snackbar = SnackbarState();
  final actions = CreditActions(store: store, snackbar: snackbar);
  return _themed(
    SnackbarHost(
      snackbar: snackbar,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final instance in store.instances)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CreditRow(
                  instance: instance,
                  showCard: true,
                  onOpen: () =>
                      snackbar.show('Would open ${instance.benefit.name}.'),
                  onLogAll: () => actions.logAll(instance),
                  onToggleMute: () => actions.toggleMute(instance),
                ),
              ),
          ],
        ),
      ),
    ),
    Brightness.dark,
  );
}

/// The credit sheet over Today, in the shape the width calls for. The sheet
/// is opened through the shared ui state, as a screen would open it.
Widget _sheetAt(Size size, String benefitId) {
  final store = _store();
  final ui = UiState()..openCredit(benefitId);
  return SizedBox.fromSize(
    size: size,
    child: RewardApp(store: store, ui: ui),
  );
}

@Preview(name: 'Credit sheet, compact bottom sheet', size: Size(402, 874))
Widget creditSheetCompact() => _sheetAt(const Size(402, 874), 'r1');

@Preview(name: 'Credit sheet, medium dialog', size: Size(768, 1024))
Widget creditSheetMedium() => _sheetAt(const Size(768, 1024), 'r1');

@Preview(name: 'Credit sheet, expanded panel', size: Size(1280, 800))
Widget creditSheetExpanded() => _sheetAt(const Size(1280, 800), 'r1');

/// The sheet's content alone, one preview per state it can be in.
Widget _sheetContent(String benefitId, Brightness brightness) {
  final store = _store();
  return _themed(
    SheetHost(
      open: true,
      widthClass: WidthClass.expanded,
      title: 'Credit',
      onClose: () {},
      sheet: CreditSheet(
        actions: CreditActions(store: store, snackbar: SnackbarState()),
        benefitId: benefitId,
        onClose: () {},
      ),
      child: const SizedBox.expand(),
    ),
    brightness,
  );
}

@Preview(name: 'Credit sheet, open with claims', size: Size(420, 900))
Widget creditSheetOpen() => _sheetContent('r1', Brightness.dark);

@Preview(name: 'Credit sheet, open, light', size: Size(420, 900))
Widget creditSheetOpenLight() => _sheetContent('r1', Brightness.light);

@Preview(name: 'Credit sheet, locked', size: Size(420, 700))
Widget creditSheetLocked() => _sheetContent('e1', Brightness.dark);

@Preview(name: 'Credit sheet, captured', size: Size(420, 700))
Widget creditSheetCaptured() => _sheetContent('u1', Brightness.dark);

@Preview(name: 'Credit sheet, untouched', size: Size(420, 700))
Widget creditSheetUntouched() => _sheetContent('u2', Brightness.dark);

/// The undo snackbar over Today, as logging a credit shows it.
Widget _snackbarAt(Size size) {
  final store = _store();
  final ui = UiState();
  ui.snackbar.show(
    'Logged \$15 on Uber Cash.',
    action: SnackbarAction(
      label: 'Undo',
      semanticsLabel: 'Undo logging Uber Cash',
      onAct: () {},
    ),
  );
  return SizedBox.fromSize(
    size: size,
    child: RewardApp(store: store, ui: ui),
  );
}

@Preview(name: 'Snackbar with Undo, compact', size: Size(402, 874))
Widget snackbarCompact() => _snackbarAt(const Size(402, 874));

@Preview(name: 'Snackbar with Undo, expanded', size: Size(1280, 800))
Widget snackbarExpanded() => _snackbarAt(const Size(1280, 800));

@Preview(name: 'Snackbar, plain', size: Size(402, 200))
Widget snackbarPlain() {
  final snackbar = SnackbarState()
    ..show('Removed \$20 from Resy Dining Credit.');
  return _themed(
    SnackbarHost(snackbar: snackbar, child: const SizedBox.expand()),
    Brightness.dark,
  );
}

@Preview(name: 'Today, interactive', size: Size(402, 874))
Widget todayInteractive() {
  final store = _store();
  return _themed(TodayScreen(store: store, ui: UiState()), Brightness.dark);
}

@Preview(name: 'Household filter', size: Size(402, 120))
Widget holderFilter() => _themed(
  Padding(
    padding: const EdgeInsets.all(16),
    child: HolderFilter(store: _store()),
  ),
  Brightness.dark,
);

@Preview(name: 'Compare sheet', size: Size(480, 700))
Widget compareSheet() {
  final store = _store();
  return _themed(
    ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final overlap = store.overlapFor('Uber Cash');
        if (overlap == null) return const Center(child: Text('Loading…'));
        return SheetHost(
          open: true,
          widthClass: WidthClass.medium,
          wide: SheetWide.dialog,
          sheetKey: const Key('compare-sheet'),
          title: overlap.label,
          onClose: () {},
          sheet: CompareSheet(
            overlap: overlap,
            actions: CreditActions(store: store, snackbar: SnackbarState()),
            onClose: () {},
            onOpenCredit: (_) {},
          ),
          child: const SizedBox.expand(),
        );
      },
    ),
    Brightness.dark,
  );
}

@Preview(name: 'Nudge preview', size: Size(402, 160))
Widget nudgePreview() => _themed(
  Align(
    alignment: Alignment.topCenter,
    child: NudgePreview(
      reminder: sampleReminder(165890, DateTime(2026, 9, 16)),
      onDismiss: () {},
      onOpen: () {},
    ),
  ),
  Brightness.dark,
);

@Preview(name: 'Nudge preview, urgent', size: Size(402, 160))
Widget nudgePreviewUrgent() => _themed(
  Align(
    alignment: Alignment.topCenter,
    child: NudgePreview(
      reminder: const Reminder(
        id: 'r',
        fireAt: 0,
        title: '\$100 on the line — last call',
        body: 'Resy Dining Credit closes tonight. Kathy’s card.',
        tag: 'last-call',
        url: '/',
        items: [],
        totalCents: 10000,
        tone: Tone.urgent,
      ),
      onDismiss: () {},
      onOpen: () {},
    ),
  ),
  Brightness.dark,
);

@Preview(name: 'Credits, dark', size: Size(402, 874))
Widget creditsDark() =>
    _themed(CreditsScreen(store: _store(), ui: UiState()), Brightness.dark);

@Preview(name: 'Credits, light', size: Size(402, 874))
Widget creditsLight() =>
    _themed(CreditsScreen(store: _store(), ui: UiState()), Brightness.light);

@Preview(name: 'Credits, expanded', size: Size(720, 900))
Widget creditsExpanded() => _themed(
  WidthClassScope(
    widthClass: WidthClass.expanded,
    child: CreditsScreen(store: _store(), ui: UiState()),
  ),
  Brightness.dark,
);

@Preview(name: 'Cards, dark', size: Size(402, 874))
Widget cardsDark() =>
    _themed(CardsScreen(store: _store(), ui: UiState()), Brightness.dark);

@Preview(name: 'Cards, light', size: Size(402, 874))
Widget cardsLight() =>
    _themed(CardsScreen(store: _store(), ui: UiState()), Brightness.light);

@Preview(name: 'Cards, medium', size: Size(560, 700))
Widget cardsMedium() => _themed(
  WidthClassScope(
    widthClass: WidthClass.medium,
    child: CardsScreen(store: _store(), ui: UiState()),
  ),
  Brightness.dark,
);

@Preview(name: 'Cards, expanded', size: Size(720, 700))
Widget cardsExpanded() => _themed(
  WidthClassScope(
    widthClass: WidthClass.expanded,
    child: CardsScreen(store: _store(), ui: UiState()),
  ),
  Brightness.dark,
);

@Preview(name: 'Cards, empty', size: Size(402, 500))
Widget cardsEmpty() {
  final store = AppStore(
    store: MemorySnapshotStore(emptyAppData()),
    clock: () => DateTime(2026, 9, 16),
  );
  store.load();
  return _themed(CardsScreen(store: store, ui: UiState()), Brightness.dark);
}

@Preview(name: 'Add a card, catalogue', size: Size(402, 874))
Widget addCardCatalogue() =>
    _themed(AddCardScreen(store: _store(), ui: UiState()), Brightness.dark);

/// The Field pattern in its three states: untouched, with a hint, and with
/// an error forced into view by a submitted form.
@Preview(name: 'Field', size: Size(402, 420))
Widget fieldStates() {
  final a = FocusNode();
  final b = FocusNode();
  final c = FocusNode();
  return _themed(
    Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
            label: 'Nickname (optional)',
            focusNode: a,
            builder: (context, control) => TextField(
              focusNode: control.focusNode,
              decoration: control.decoration,
            ),
          ),
          const SizedBox(height: 16),
          Field(
            label: 'Whose card is it?',
            required: true,
            hint: 'The name is how their credits stay apart.',
            focusNode: b,
            builder: (context, control) => TextField(
              focusNode: control.focusNode,
              decoration: control.decoration,
            ),
          ),
          const SizedBox(height: 16),
          Field(
            label: 'Account opened / renews on',
            required: true,
            error: anniversaryError('2026-13-40'),
            submitted: true,
            focusNode: c,
            builder: (context, control) => TextField(
              controller: TextEditingController(text: '2026-13-40'),
              focusNode: control.focusNode,
              decoration: control.decoration,
            ),
          ),
        ],
      ),
    ),
    Brightness.dark,
  );
}

@Preview(name: 'Card editor', size: Size(402, 874))
Widget cardEditor() => _themed(
  CardEditorScreen(store: _store(), id: 'kathy', ui: UiState()),
  Brightness.dark,
);

@Preview(name: 'Card editor, expanded', size: Size(1280, 800))
Widget cardEditorExpanded() => _themed(
  CardEditorScreen(store: _store(), id: 'kathy', ui: UiState()),
  Brightness.dark,
);

@Preview(name: 'Benefit editor', size: Size(402, 1200))
Widget benefitEditor() => _themed(
  BenefitEditorScreen(store: _store(), id: 'e1', ui: UiState()),
  Brightness.dark,
);

@Preview(name: 'Benefit editor, light', size: Size(402, 1200))
Widget benefitEditorLight() => _themed(
  BenefitEditorScreen(store: _store(), id: 'r1', ui: UiState()),
  Brightness.light,
);

@Preview(name: 'Editor, not found', size: Size(402, 300))
Widget editorNotFound() => _themed(
  CardEditorScreen(store: _store(), id: 'gone', ui: UiState()),
  Brightness.dark,
);

@Preview(name: 'Value, dark', size: Size(402, 1100))
Widget valueDark() => _themed(ValueScreen(store: _store()), Brightness.dark);

@Preview(name: 'Value, light', size: Size(402, 1100))
Widget valueLight() => _themed(ValueScreen(store: _store()), Brightness.light);

@Preview(name: 'Value, expanded', size: Size(720, 900))
Widget valueExpanded() => _themed(
  WidthClassScope(
    widthClass: WidthClass.expanded,
    child: ValueScreen(store: _store()),
  ),
  Brightness.dark,
);

@Preview(name: 'Settings, reminders off', size: Size(402, 874))
Widget settingsOff() =>
    _themed(SettingsScreen(store: _store(), ui: UiState()), Brightness.dark);

@Preview(name: 'Settings, reminders on', size: Size(402, 1100))
Widget settingsOn() {
  final store = _store();
  store.updateNotificationSettings((n) => n.copyWith(enabled: true));
  return _themed(SettingsScreen(store: store, ui: UiState()), Brightness.dark);
}

@Preview(name: 'Settings, light', size: Size(402, 874))
Widget settingsLight() =>
    _themed(SettingsScreen(store: _store(), ui: UiState()), Brightness.light);

@Preview(name: 'Not found', size: Size(402, 500))
Widget notFound() => _themed(const NotFoundScreen(), Brightness.dark);
