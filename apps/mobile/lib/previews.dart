import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/widget_previews.dart';

import 'data/household_api.dart';
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
import 'shell/logo_hand_off.dart';
import 'shell/width_class.dart';
import 'theme/theme.dart';
import 'widgets/all_caught_up.dart';
import 'widgets/brand_lockup.dart';
import 'widgets/brand_logo.dart';
import 'widgets/credit_row.dart';
import 'widgets/catalog_filter_panel.dart';
import 'widgets/compare_sheet.dart';
import 'widgets/credit_sheet.dart';
import 'widgets/empty_card_slot.dart';
import 'widgets/field.dart';
import 'widgets/give_card_sheet.dart';
import 'widgets/nothing_due_soon.dart';
import 'widgets/notification_level_control.dart';
import 'widgets/share_choices.dart';
import 'widgets/sheet_host.dart';
import 'widgets/today_caught_up.dart';
import 'widgets/today_headline.dart';
import 'widgets/value_bar.dart';
import 'widgets/snackbar_host.dart';
import 'logic/session.dart';
import 'screens/sign_in_screen.dart';
import 'screens/welcome_hero.dart';
import 'screens/welcome_heroes.dart';
import 'screens/welcome_premium_mocks.dart';
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

/// A slide's picture in its hero at a phone's width.
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

@Preview(name: 'Welcome hero, timely reminders, dark', size: Size(402, 460))
Widget timelyRemindersHeroDark() =>
    _heroIn(const TimelyRemindersHero(), Brightness.dark);

@Preview(name: 'Welcome hero, timely reminders, light', size: Size(402, 460))
Widget timelyRemindersHeroLight() =>
    _heroIn(const TimelyRemindersHero(), Brightness.light);

@Preview(name: 'Welcome hero, premium features, dark', size: Size(402, 460))
Widget premiumFeaturesHeroDark() =>
    _heroIn(const PremiumFeaturesHero(), Brightness.dark);

@Preview(name: 'Welcome hero, premium features, light', size: Size(402, 460))
Widget premiumFeaturesHeroLight() =>
    _heroIn(const PremiumFeaturesHero(), Brightness.light);

/// The empty-state illustration at the size Today draws it.
Widget _slotIn(Brightness brightness) =>
    _themed(const Center(child: EmptyCardSlot(size: 160)), brightness);

@Preview(name: 'Empty card slot, dark', size: Size(200, 200))
Widget emptyCardSlotDark() => _slotIn(Brightness.dark);

@Preview(name: 'Empty card slot, light', size: Size(200, 200))
Widget emptyCardSlotLight() => _slotIn(Brightness.light);

/// The all-caught-up illustration at the size Today draws it.
Widget _caughtUpIn(Brightness brightness) =>
    _themed(const Center(child: AllCaughtUp(size: 132)), brightness);

@Preview(name: 'All caught up, dark', size: Size(180, 180))
Widget allCaughtUpDark() => _caughtUpIn(Brightness.dark);

@Preview(name: 'All caught up, light', size: Size(180, 180))
Widget allCaughtUpLight() => _caughtUpIn(Brightness.light);

/// The value bar at a phone card's width, in each shape it takes.
Widget _valueBarIn(ValueBreakdown breakdown, Brightness brightness) => _themed(
  Padding(
    padding: const EdgeInsets.all(16),
    child: ValueBar(breakdown: breakdown),
  ),
  brightness,
);

const _fourSegments = ValueBreakdown(
  earnedCents: 54000,
  availableCents: 77000,
  missedCents: 18000,
  optOutCents: 36000,
);

const _narrowMissed = ValueBreakdown(
  earnedCents: 61000,
  availableCents: 29000,
  missedCents: 1500,
  optOutCents: 20000,
);

const _singleSegment = ValueBreakdown(availableCents: 30000);

@Preview(name: 'Value bar, four segments, dark', size: Size(402, 120))
Widget valueBarDark() => _valueBarIn(_fourSegments, Brightness.dark);

@Preview(name: 'Value bar, four segments, light', size: Size(402, 120))
Widget valueBarLight() => _valueBarIn(_fourSegments, Brightness.light);

@Preview(name: 'Value bar, narrow missed, dark', size: Size(402, 120))
Widget valueBarNarrowDark() => _valueBarIn(_narrowMissed, Brightness.dark);

@Preview(name: 'Value bar, narrow missed, light', size: Size(402, 120))
Widget valueBarNarrowLight() => _valueBarIn(_narrowMissed, Brightness.light);

@Preview(name: 'Value bar, single segment, dark', size: Size(402, 120))
Widget valueBarSingleDark() => _valueBarIn(_singleSegment, Brightness.dark);

@Preview(name: 'Value bar, single segment, light', size: Size(402, 120))
Widget valueBarSingleLight() => _valueBarIn(_singleSegment, Brightness.light);

@Preview(name: 'Value bar, empty, dark', size: Size(402, 120))
Widget valueBarEmptyDark() => _valueBarIn(ValueBreakdown.zero, Brightness.dark);

@Preview(name: 'Value bar, empty, light', size: Size(402, 120))
Widget valueBarEmptyLight() =>
    _valueBarIn(ValueBreakdown.zero, Brightness.light);

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

const _kathy = Person(id: 'user-kathy', name: 'Kathy');

/// The join screen for an invite to all of Kathy's cards at view, or to two
/// of them at record.
Widget _joinFor(bool allCards, Brightness brightness) => _themed(
  JoinScreen(
    store: _sharedStore(
      CardAccess.view,
      offer: allCards
          ? const InviteOffer(
              owner: _kathy,
              access: CardAccess.view,
              allCards: true,
            )
          : const InviteOffer(
              owner: _kathy,
              access: CardAccess.record,
              allCards: false,
              cardCount: 2,
            ),
    ),
    code: 'ABCD2345',
  ),
  brightness,
);

@Preview(name: 'Accept an invite, all cards, dark', size: Size(402, 874))
Widget joinAllDark() => _joinFor(true, Brightness.dark);

@Preview(name: 'Accept an invite, all cards, light', size: Size(402, 874))
Widget joinAllLight() => _joinFor(true, Brightness.light);

@Preview(name: 'Accept an invite, chosen cards, dark', size: Size(402, 874))
Widget joinChosenDark() => _joinFor(false, Brightness.dark);

@Preview(name: 'Accept an invite, chosen cards, light', size: Size(402, 874))
Widget joinChosenLight() => _joinFor(false, Brightness.light);

/// Settings with shares both ways: Bob sees your cards, Kathy shares hers.
@Preview(name: 'Household sharing, dark', size: Size(402, 1600))
Widget householdSharingDark() => _themed(
  SettingsScreen(store: _sharedStore(CardAccess.record)),
  Brightness.dark,
);

@Preview(name: 'Household sharing, light', size: Size(402, 1600))
Widget householdSharingLight() => _themed(
  SettingsScreen(store: _sharedStore(CardAccess.record)),
  Brightness.light,
);

/// The share choices at record with one card chosen.
Widget _shareChoicesIn(Brightness brightness) => _themed(
  ShareChoices(
    title: 'Share your cards',
    cards: sampleHousehold().cards,
    action: 'Create and share',
    access: CardAccess.record,
    cardIds: const ['jim'],
  ),
  brightness,
);

@Preview(name: 'Share choices, dark', size: Size(402, 760))
Widget shareChoicesDark() => _shareChoicesIn(Brightness.dark);

@Preview(name: 'Share choices, light', size: Size(402, 760))
Widget shareChoicesLight() => _shareChoicesIn(Brightness.light);

/// Handing Jim's Platinum to one of the two people it is shared with.
Widget _giveCardIn(Brightness brightness) => _themed(
  const GiveCardSheet(
    cardName: 'Jim’s Platinum',
    people: [
      _kathy,
      Person(id: 'user-bob', name: 'Bob', email: 'bob@example.com'),
    ],
  ),
  brightness,
);

@Preview(name: 'Give a card, dark', size: Size(402, 400))
Widget giveCardDark() => _giveCardIn(Brightness.dark);

@Preview(name: 'Give a card, light', size: Size(402, 400))
Widget giveCardLight() => _giveCardIn(Brightness.light);

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

/// Today's headline once nothing is claimable, over the sample household's
/// two Uber Cash credits; the locked variant has $200 still locked.
Widget _caughtUpHeadline(Brightness brightness, {int lockedCents = 0}) {
  final uber = sampleHousehold().benefits.where((b) => b.name == 'Uber Cash');
  return _themed(
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: TodayCaughtUp(
        eyebrow: todayEyebrow(sampleToday),
        today: sampleToday,
        capturedCents: 3000,
        lockedCents: lockedCents,
        cards: 2,
        next: NextOpening(on: '2026-10-01', benefits: uber.toList()),
      ),
    ),
    brightness,
  );
}

@Preview(name: 'Today, all caught up, dark', size: Size(402, 520))
Widget todayCaughtUpDark() => _caughtUpHeadline(Brightness.dark);

@Preview(name: 'Today, all caught up, light', size: Size(402, 520))
Widget todayCaughtUpLight() => _caughtUpHeadline(Brightness.light);

@Preview(name: 'Today, all caught up, locked', size: Size(402, 420))
Widget todayCaughtUpLocked() =>
    _caughtUpHeadline(Brightness.dark, lockedCents: 20000);

/// The note where Use soon would be, on 2 October 2026, when the sample
/// household's Resy credit is open until Dec 31.
Widget _nothingDueSoonIn(Brightness brightness) {
  const on = '2026-10-02';
  final resy = currentInstances(
    sampleHousehold(),
    on,
  ).firstWhere((i) => i.benefit.name == 'Resy Dining Credit');
  return _themed(
    Padding(
      padding: const EdgeInsets.all(16),
      child: NothingDueSoon(next: resy, today: on, onOpenCredits: () {}),
    ),
    brightness,
  );
}

@Preview(name: 'Nothing due soon, dark', size: Size(402, 160))
Widget nothingDueSoonDark() => _nothingDueSoonIn(Brightness.dark);

@Preview(name: 'Nothing due soon, light', size: Size(402, 160))
Widget nothingDueSoonLight() => _nothingDueSoonIn(Brightness.light);

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

/// The cold start's logo hand-off, played once as the preview loads, onto
/// the lockup in a compact bar.
@Preview(name: 'Logo hand-off onto the app bar', size: Size(402, 874))
Widget logoHandOff() => MaterialApp(
  theme: nocturneTheme(Brightness.light),
  builder: (context, child) => LogoHandOff(play: true, child: child!),
  home: const Scaffold(appBar: BrandAppBar(widthClass: WidthClass.compact)),
);

/// The same hand-off onto Sign in's stacked logo, in the dark theme.
@Preview(name: 'Logo hand-off onto the stacked logo', size: Size(402, 874))
Widget logoHandOffStacked() => MaterialApp(
  theme: nocturneTheme(Brightness.dark),
  builder: (context, child) => LogoHandOff(play: true, child: child!),
  home: const Scaffold(body: Center(child: BrandLogo.stacked())),
);

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

/// The notification levels control on a sample credit, choosable, or with
/// its card silenced.
Widget _levels(Brightness brightness, {bool cardMuted = false}) {
  final benefit = sampleHousehold().benefits.first;
  var level = NotificationLevel.periodically;
  return _themed(
    StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.all(24),
        child: NotificationLevelControl(
          benefit: benefit,
          level: level,
          cardMuted: cardMuted,
          onChanged: (next) => setState(() => level = next),
        ),
      ),
    ),
    brightness,
  );
}

@Preview(name: 'Notification levels, dark', size: Size(402, 200))
Widget notificationLevelsDark() => _levels(Brightness.dark);

@Preview(name: 'Notification levels, light', size: Size(402, 200))
Widget notificationLevelsLight() => _levels(Brightness.light);

@Preview(name: 'Notification levels, card silenced', size: Size(402, 200))
Widget notificationLevelsCardMuted() =>
    _levels(Brightness.dark, cardMuted: true);

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

/// A service tier for previews that serves the preview household, with
/// Kathy's card hers, labelled "Platinum" and shared at [access]; the
/// shares both ways (Bob sees your cards); and [offer] for an invite.
class _SharedPreviewApi implements HouseholdApi {
  _SharedPreviewApi(this.access, {this.offer});

  final CardAccess access;
  final InviteOffer? offer;

  @override
  Future<InviteOffer> readInvite(String code) async => offer!;

  @override
  Future<CardShares> shares() async => CardShares(
    given: const [
      CardShare(
        person: Person(id: 'user-bob', name: 'Bob'),
        access: CardAccess.view,
        allCards: true,
      ),
    ],
    received: [
      CardShare(
        person: _kathy,
        access: access,
        allCards: false,
        cardIds: const ['kathy'],
      ),
    ],
  );

  @override
  Future<HouseholdSnapshot> householdData() async {
    final household = sampleHousehold();
    return HouseholdSnapshot(
      data: household.copyWith(
        cards: [
          for (final card in household.cards)
            card.id == 'kathy'
                ? card.copyWith(ownerId: 'user-kathy', label: 'Platinum')
                : card,
        ],
      ),
      access: {'jim': CardAccess.owner, 'kathy': access},
      people: const {'user-kathy': _kathy},
    );
  }

  @override
  Future<MemberPreferences> preferences() async => defaultMemberPreferences;

  @override
  Future<List<CardTemplate>> catalog() async => [
    for (final template in cardTemplates)
      if (template.id != 'blank') template,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppStore _sharedStore(CardAccess access, {InviteOffer? offer}) {
  final store = AppStore(
    store: MemorySnapshotStore(),
    api: _SharedPreviewApi(access, offer: offer),
    clock: () => DateTime(2026, 9, 16),
  );
  store.load();
  return store;
}

/// The Resy credit on Kathy's card, as someone she shares it with sees it.
Widget _sharedSheet(CardAccess access, Brightness brightness) {
  final store = _sharedStore(access);
  return _themed(
    SheetHost(
      open: true,
      widthClass: WidthClass.expanded,
      title: 'Credit',
      onClose: () {},
      sheet: CreditSheet(
        actions: CreditActions(store: store, snackbar: SnackbarState()),
        benefitId: 'r1',
        onClose: () {},
      ),
      child: const SizedBox.expand(),
    ),
    brightness,
  );
}

@Preview(name: 'Credit sheet, shared to view, dark', size: Size(420, 900))
Widget creditSheetSharedViewDark() =>
    _sharedSheet(CardAccess.view, Brightness.dark);

@Preview(name: 'Credit sheet, shared to view, light', size: Size(420, 900))
Widget creditSheetSharedViewLight() =>
    _sharedSheet(CardAccess.view, Brightness.light);

@Preview(name: 'Credit sheet, shared to record, dark', size: Size(420, 900))
Widget creditSheetSharedRecordDark() =>
    _sharedSheet(CardAccess.record, Brightness.dark);

@Preview(name: 'Credit sheet, shared to record, light', size: Size(420, 900))
Widget creditSheetSharedRecordLight() =>
    _sharedSheet(CardAccess.record, Brightness.light);

@Preview(name: 'Cards, shared with you, dark', size: Size(402, 1400))
Widget cardsSharedDark() => _themed(
  CardsScreen(store: _sharedStore(CardAccess.view), ui: UiState()),
  Brightness.dark,
);

@Preview(name: 'Cards, shared with you, light', size: Size(402, 1400))
Widget cardsSharedLight() => _themed(
  CardsScreen(store: _sharedStore(CardAccess.record), ui: UiState()),
  Brightness.light,
);

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

AppStore _emptyStore() {
  final store = AppStore(
    store: MemorySnapshotStore(emptyAppData()),
    clock: () => DateTime(2026, 9, 16),
  );
  store.load();
  return store;
}

@Preview(name: 'Today, empty, dark', size: Size(402, 874))
Widget todayEmptyDark() =>
    _themed(TodayScreen(store: _emptyStore()), Brightness.dark);

@Preview(name: 'Today, empty, light', size: Size(402, 874))
Widget todayEmptyLight() =>
    _themed(TodayScreen(store: _emptyStore()), Brightness.light);

/// From expanded the illustration moves beside the text.
@Preview(name: 'Today, empty, expanded', size: Size(1280, 832))
Widget todayEmptyExpanded() => _themed(
  WidthClassScope(
    widthClass: WidthClass.expanded,
    child: TodayScreen(store: _emptyStore()),
  ),
  Brightness.dark,
);

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
