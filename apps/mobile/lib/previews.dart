import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/widget_previews.dart';

import 'data/snapshot_store.dart';
import 'logic/app_store.dart';
import 'logic/catalog_filter_controller.dart';
import 'logic/credit_actions.dart';
import 'logic/sample_household.dart';
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
import 'shell/brand_app_bar.dart';
import 'shell/width_class.dart';
import 'theme/theme.dart';
import 'widgets/brand_lockup.dart';
import 'widgets/credit_row.dart';
import 'widgets/catalog_filter_panel.dart';
import 'widgets/compare_sheet.dart';
import 'widgets/credit_sheet.dart';
import 'widgets/field.dart';
import 'widgets/sheet_host.dart';
import 'widgets/snackbar_host.dart';
import 'logic/session.dart';
import 'screens/sign_in_screen.dart';
import 'screens/welcome_hero.dart';
import 'screens/welcome_heroes.dart';
import 'screens/welcome_screen.dart';
import 'screens/join_screen.dart';
import 'screens/convert_screen.dart';

/// Widget previews for every UI component, on a small household so the
/// screens render populated rather than empty.

AppStore _store() {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => DateTime(2026, 9, 16),
  );
  store.load();
  return store;
}

Widget _themed(Widget child, Brightness brightness) => MaterialApp(
  theme: nocturneTheme(brightness),
  home: Scaffold(body: SafeArea(child: child)),
);

/// The lockup in the width the app bar gives it: a 402 window, then a 300
/// one where only the wordmark fits.
Widget _lockupIn(double window, Brightness brightness) => _themed(
  Padding(
    padding: const EdgeInsets.all(20),
    child: SizedBox(width: window - 84, child: const BrandLockup()),
  ),
  brightness,
);

@Preview(name: 'Brand lockup, dark', size: Size(402, 72))
Widget brandLockupDark() => _lockupIn(402, Brightness.dark);

@Preview(name: 'Brand lockup, light', size: Size(402, 72))
Widget brandLockupLight() => _lockupIn(402, Brightness.light);

@Preview(name: 'Brand lockup, 300 wide shows the wordmark', size: Size(300, 72))
Widget brandLockupNarrow() => _lockupIn(300, Brightness.light);

@Preview(name: 'Welcome slideshow, dark', size: Size(402, 874))
Widget welcomeDark() => _themed(WelcomeScreen(onDone: () {}), Brightness.dark);

@Preview(name: 'Welcome slideshow, light', size: Size(402, 874))
Widget welcomeLight() =>
    _themed(WelcomeScreen(onDone: () {}), Brightness.light);

/// A slide's picture in its panel at a phone's width.
Widget _heroIn(Widget hero, Brightness brightness) => _themed(
  Padding(
    padding: const EdgeInsets.all(16.8),
    child: SizedBox(height: 420, child: WelcomeHero(child: hero)),
  ),
  brightness,
);

@Preview(name: 'Welcome hero, upcoming rewards, dark', size: Size(402, 460))
Widget upcomingRewardsHeroDark() =>
    _heroIn(const UpcomingRewardsHero(), Brightness.dark);

@Preview(name: 'Welcome hero, upcoming rewards, light', size: Size(402, 460))
Widget upcomingRewardsHeroLight() =>
    _heroIn(const UpcomingRewardsHero(), Brightness.light);

@Preview(name: 'Sign-in, dark', size: Size(402, 874))
Widget signInDark() => _themed(
  SignInScreen(auth: UnconfiguredAuth(), onLearnMore: () {}),
  Brightness.dark,
);

@Preview(name: 'Sign-in, expanded', size: Size(1280, 800))
Widget signInExpanded() => _themed(
  SignInScreen(auth: UnconfiguredAuth(), onLearnMore: () {}),
  Brightness.light,
);

@Preview(name: 'Join a household, dark', size: Size(402, 874))
Widget joinDark() =>
    _themed(JoinScreen(store: _store(), code: 'ABCD2345'), Brightness.dark);

@Preview(name: 'Join a household, light', size: Size(402, 874))
Widget joinLight() =>
    _themed(JoinScreen(store: _store(), code: 'ABCD2345'), Brightness.light);

/// The preview household with its first card linked to the Platinum
/// template, so Cards shows both groups.
AppStore _linkedStore() {
  final household = sampleHousehold();
  final store = AppStore(
    store: MemorySnapshotStore(
      household.copyWith(
        cards: [
          household.cards.first.copyWith(templateId: 'amex-platinum'),
          ...household.cards.skip(1),
        ],
      ),
    ),
    clock: () => DateTime(2026, 9, 16),
  );
  store.load();
  return store;
}

@Preview(name: 'Cards, system and user groups', size: Size(402, 1400))
Widget cardsGroups() =>
    _themed(CardsScreen(store: _linkedStore()), Brightness.dark);

@Preview(name: 'Change the terms', size: Size(402, 874))
Widget convert() => _themed(
  ConvertScreen(store: _linkedStore(), cardId: 'jim'),
  Brightness.dark,
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

/// The tab bar alone in the pane it spans: the window at compact, the
/// window less the rail from medium.
Widget _barIn(WidthClass widthClass) => MaterialApp(
  theme: nocturneTheme(Brightness.dark),
  home: Scaffold(
    appBar: BrandAppBar(widthClass: widthClass, onSettings: () {}),
  ),
);

@Preview(name: 'Brand app bar, compact', size: Size(402, 64))
Widget brandAppBarCompact() => _barIn(WidthClass.compact);

@Preview(name: 'Brand app bar, medium pane', size: Size(688, 64))
Widget brandAppBarMedium() => _barIn(WidthClass.medium);

@Preview(name: 'Brand app bar, expanded pane', size: Size(1080, 64))
Widget brandAppBarExpanded() => _barIn(WidthClass.expanded);

@Preview(name: 'Placeholder screen', size: Size(402, 300))
Widget stubScreen() => _themed(const StubScreen('Cards'), Brightness.dark);

@Preview(name: 'Credit rows, every tone', size: Size(402, 400))
Widget creditRows() {
  final instances = currentInstances(sampleHousehold(), sampleToday);
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
/// to park on Silence and Opt out side by side, tap the bell, or tap the
/// row; the snackbar shows the undo.
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
                  onOptOut: () => actions.optOut(instance),
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

/// A rolling credit with no claim yet: "Eligible now", no window range.
@Preview(name: 'Credit sheet, rolling', size: Size(420, 700))
Widget creditSheetRolling() => _sheetContent('g1', Brightness.dark);

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

/// From expanded the catalogue puts the filter panel beside the list.
@Preview(name: 'Add a card, catalogue, expanded', size: Size(1280, 800))
Widget addCardCatalogueExpanded() =>
    _themed(AddCardScreen(store: _store(), ui: UiState()), Brightness.dark);

/// The filter panel alone, with Chase checked so the counts follow it and
/// the zero-count options dim.
@Preview(name: 'Catalogue filter panel', size: Size(260, 1200))
Widget catalogFilterPanel() => _themed(
  CatalogFilterPanel(
    controller: CatalogFilterController()
      ..update((f) => f.toggleIssuer('Chase')),
    padding: const EdgeInsets.all(16),
  ),
  Brightness.dark,
);

/// The compact sheet's contents, with two values checked: "Show N" follows
/// the live result count.
@Preview(name: 'Catalogue filter sheet', size: Size(402, 700))
Widget catalogFilterSheet() => _themed(
  CatalogFilterSheet(
    controller: CatalogFilterController()
      ..update((f) => f.toggleIssuer('Chase').toggleFeeBand(FeeBand.from600)),
  ),
  Brightness.dark,
);

/// Uber selected: each listed card tags the credits that matched.
@Preview(name: 'Add a card, matched credits', size: Size(1280, 800))
Widget addCardMatched() => _themed(
  AddCardScreen(
    store: _store(),
    ui: UiState(),
    initialFilter: const CatalogFilter().toggleMerchant('Uber'),
  ),
  Brightness.dark,
);

/// Step two with the Business Platinum picked: the kind chips start on
/// Business because the template says so.
@Preview(name: 'Add a card, details', size: Size(402, 874))
Widget addCardDetails() => _themed(
  AddCardScreen(
    store: _store(),
    ui: UiState(),
    initialTemplate: findTemplate('amex-business-platinum'),
  ),
  Brightness.dark,
);

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

/// A rolling credit: the cadence picker on Rolling, the months field in
/// place of the anchor chips and the window preview.
@Preview(name: 'Benefit editor, rolling', size: Size(402, 1200))
Widget benefitEditorRolling() => _themed(
  BenefitEditorScreen(store: _store(), id: 'g1', ui: UiState()),
  Brightness.dark,
);

/// A credit gated behind a spend threshold: the "Unlocks after spending"
/// field is filled and the "Spend reached this year" switch is shown.
@Preview(name: 'Benefit editor, spend threshold', size: Size(402, 1300))
Widget benefitEditorSpendThreshold() => _themed(
  BenefitEditorScreen(store: _store(), id: 'd1', ui: UiState()),
  Brightness.dark,
);

/// A credit the household opted out of: the "Opted out" switch is on.
@Preview(name: 'Benefit editor, opted out', size: Size(402, 1200))
Widget benefitEditorOptedOut() => _themed(
  BenefitEditorScreen(store: _store(), id: 'o1', ui: UiState()),
  Brightness.dark,
);

/// A credit the issuer has given an end date: the "Ends on" field is filled
/// and the window preview closes on it.
@Preview(name: 'Benefit editor, ends on', size: Size(402, 1200))
Widget benefitEditorEndsOn() => _themed(
  BenefitEditorScreen(store: _store(), id: 'r1', ui: UiState()),
  Brightness.dark,
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
  store.updatePreferences((p) => p.copyWith(enabled: true));
  return _themed(SettingsScreen(store: store, ui: UiState()), Brightness.dark);
}

@Preview(name: 'Settings, light', size: Size(402, 874))
Widget settingsLight() =>
    _themed(SettingsScreen(store: _store(), ui: UiState()), Brightness.light);

@Preview(name: 'Not found, dark', size: Size(402, 600))
Widget notFound() => _themed(const NotFoundScreen(), Brightness.dark);

@Preview(name: 'Not found, light, signed in', size: Size(402, 600))
Widget notFoundLight() =>
    _themed(const NotFoundScreen(showSettings: true), Brightness.light);
