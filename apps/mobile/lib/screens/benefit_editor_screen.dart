import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/editor_scaffold.dart';
import '../widgets/field.dart';
import '../widgets/switch_row.dart';

/// Editing one credit.
///
/// The cadence and anchor controls show the window they produce, live:
/// "Sep 1 – Sep 30" under a monthly calendar credit, and a cardmember window
/// under an anniversary one. Those two fields decide whether a reminder
/// arrives in time, and they are the ones users most often get wrong. Fields
/// write the store as soon as their value is valid; an invalid one shows its
/// error and waits.
class BenefitEditorScreen extends StatefulWidget {
  const BenefitEditorScreen({
    super.key,
    required this.store,
    required this.id,
    this.ui,
  });

  final AppStore store;
  final String id;
  final UiState? ui;

  @override
  State<BenefitEditorScreen> createState() => _BenefitEditorScreenState();
}

class _BenefitEditorScreenState extends State<BenefitEditorScreen> {
  final _name = TextEditingController();
  final _value = TextEditingController();
  final _merchant = TextEditingController();
  final _url = TextEditingController();
  final _interval = TextEditingController();
  final _spend = TextEditingController();
  final _endsOn = TextEditingController();
  final _steps = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'name');
  final _valueFocus = FocusNode(debugLabel: 'value');
  final _merchantFocus = FocusNode(debugLabel: 'merchant');
  final _urlFocus = FocusNode(debugLabel: 'url');
  final _intervalFocus = FocusNode(debugLabel: 'interval');
  final _spendFocus = FocusNode(debugLabel: 'spend');
  final _endsOnFocus = FocusNode(debugLabel: 'endsOn');
  final _stepsFocus = FocusNode(debugLabel: 'steps');

  AppStore get store => widget.store;

  Benefit? get benefit {
    for (final b in store.data?.benefits ?? const <Benefit>[]) {
      if (b.id == widget.id) return b;
    }
    return null;
  }

  Card? cardOf(Benefit benefit) {
    for (final c in store.data?.cards ?? const <Card>[]) {
      if (c.id == benefit.cardId) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final current = benefit;
    if (current != null) {
      _name.text = current.name;
      _value.text = (current.valueCents / 100).toString();
      _merchant.text = current.merchant ?? '';
      _url.text = current.enrollmentUrl ?? '';
      _interval.text = current.intervalMonths?.toString() ?? '';
      final threshold = current.spendThresholdCents;
      _spend.text = threshold == null ? '' : (threshold / 100).toString();
      _endsOn.text = current.endsOn ?? '';
      _steps.text = current.redemptionSteps.join('\n');
    }
    for (final c in _controllers) {
      c.addListener(_changed);
    }
  }

  List<TextEditingController> get _controllers => [
    _name,
    _value,
    _merchant,
    _url,
    _interval,
    _spend,
    _endsOn,
    _steps,
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in [
      _nameFocus,
      _valueFocus,
      _merchantFocus,
      _urlFocus,
      _intervalFocus,
      _spendFocus,
      _endsOnFocus,
      _stepsFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  String? get _nameError =>
      requiredError(_name.text, 'Enter what the credit is called.');
  String? get _valueError => positiveMoneyError(_value.text);
  String? get _urlError => enrollmentUrlError(_url.text);
  String? get _endsOnError => endsOnError(_endsOn.text);
  String? get _spendError =>
      _spend.text.trim().isEmpty ? null : moneyError(_spend.text);
  String? get _intervalError =>
      intervalMonthsError(benefit?.cadence ?? Cadence.monthly, _interval.text);
  bool get _unsaved =>
      _nameError != null ||
      _valueError != null ||
      _urlError != null ||
      _intervalError != null ||
      _spendError != null ||
      _endsOnError != null;

  /// Writes every valid draft; the invalid ones wait, showing their error.
  void _changed() {
    final current = benefit;
    if (current == null) return;
    final name = _name.text.trim();
    final cents = parseMoney(_value.text);
    final merchant = _merchant.text.trim();
    final url = _url.text.trim();
    final interval = int.tryParse(_interval.text.trim());
    final spend = _spend.text.trim();
    final spendCents = spend.isEmpty ? null : parseMoney(spend);
    final endsOn = _endsOn.text.trim();
    final steps = _steps.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final patch = <Benefit Function(Benefit)>[
      if (_nameError == null && name != current.name)
        (b) => b.copyWith(name: name),
      if (cents != null && cents > 0 && cents != current.valueCents)
        (b) => b.copyWith(valueCents: cents),
      if ((current.merchant ?? '') != merchant)
        (b) => b.copyWith(merchant: merchant.isEmpty ? null : merchant),
      if (_urlError == null && (current.enrollmentUrl ?? '') != url)
        (b) => b.copyWith(enrollmentUrl: url.isEmpty ? null : url),
      if (_intervalError == null &&
          interval != null &&
          interval != current.intervalMonths)
        (b) => b.copyWith(intervalMonths: interval),
      if (_spendError == null && spendCents != current.spendThresholdCents)
        (b) => b.copyWith(spendThresholdCents: spendCents),
      if (_endsOnError == null && (current.endsOn ?? '') != endsOn)
        (b) => b.copyWith(endsOn: endsOn.isEmpty ? null : endsOn),
      if (steps.join('\n') != current.redemptionSteps.join('\n'))
        (b) => b.copyWith(redemptionSteps: steps),
    ];
    if (patch.isNotEmpty) {
      store.updateBenefit(current.id, (b) => patch.fold(b, (b, p) => p(b)));
    }
    setState(() {});
  }

  void _patch(Benefit current, Benefit Function(Benefit) change) =>
      store.updateBenefit(current.id, change);

  String _home(Benefit? current) {
    final card = current == null ? null : cardOf(current);
    return card == null ? Paths.credits : cardPath(card.id);
  }

  Future<void> _back() async {
    final home = _home(benefit);
    if (!_unsaved || await confirmLeave(context)) {
      if (mounted) context.go(home);
    }
  }

  Future<void> _delete() async {
    final current = benefit;
    if (current == null) return;
    if (!await confirmDelete(context, current.name)) return;
    final home = _home(current);
    await store.deleteBenefit(current.id);
    widget.ui?.snackbar.show('Credit deleted.');
    if (mounted) context.go(home);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final current = benefit;
        if (current == null) {
          return EditorScaffold(
            title: 'Credit not found',
            onBack: () => context.go(Paths.credits),
            snackbar: widget.ui?.snackbar,
            child: const NotFoundBody('That credit is no longer here.'),
          );
        }
        final card = cardOf(current);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: EditorScaffold(
            title: current.name,
            subtitle: card == null ? null : cardLabel(card),
            onBack: _back,
            action: EditorAction(
              icon: Icons.delete_outline,
              label: 'Delete this credit',
              onAct: _delete,
            ),
            snackbar: widget.ui?.snackbar,
            child: Builder(builder: (context) => _form(context, current, card)),
          ),
        );
      },
    );
  }

  Widget _form(BuildContext context, Benefit current, Card? card) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);
    final today = store.today;
    final cycle = card == null ? null : cycleFor(current, card, today);
    // A credit the catalogue keeps up to date: its terms are the
    // catalogue's; enrolment, spend, tracking and the page are the
    // household's.
    final linked = current.templateBenefitId != null;

    Widget field(
      String key,
      String label, {
      String? hint,
      String? error,
      required TextEditingController controller,
      required FocusNode focusNode,
      bool required = false,
      TextInputType? keyboardType,
      int? maxLines = 1,
    }) => Field(
      label: label,
      hint: hint,
      error: error,
      required: required,
      focusNode: focusNode,
      builder: (context, control) => TextField(
        key: Key(key),
        controller: controller,
        focusNode: control.focusNode,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: linked && key != 'field-url',
        decoration: control.decoration,
      ),
    );

    final cadence = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<Cadence>(
          key: const Key('field-cadence'),
          isExpanded: true,
          initialValue: current.cadence,
          decoration: const InputDecoration(labelText: 'How often it resets'),
          items: [
            for (final cadence in Cadence.values)
              DropdownMenuItem(
                value: cadence,
                child: Text(cadenceLabel(cadence)),
              ),
          ],
          onChanged: linked
              ? null
              : (cadence) {
                  if (cadence != null) {
                    _patch(current, (b) => b.copyWith(cadence: cadence));
                  }
                },
        ),
        if (current.cadence != Cadence.manual &&
            current.cadence != Cadence.rolling)
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: Text(
              'Reminders at ${ladderSummary(current.cadence)} days out.',
              style: note,
            ),
          ),
        if (current.cadence == Cadence.rolling)
          Padding(
            padding: const EdgeInsets.only(top: Space.s3),
            child: field(
              'field-interval',
              'Months between claims',
              hint:
                  'Counted from the day you claim it. Global Entry is every 48.',
              required: true,
              error: _intervalError,
              controller: _interval,
              focusNode: _intervalFocus,
              keyboardType: TextInputType.number,
            ),
          ),
      ],
    );

    final anchor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Measured from', style: note),
        const SizedBox(height: Space.s2),
        // Chips rather than a segmented button: two labels wrap onto two
        // lines at a large text size instead of overflowing the column.
        Semantics(
          label: 'Measured from',
          container: true,
          explicitChildNodes: true,
          child: Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final (anchor, label) in const [
                (CycleAnchor.calendar, 'The calendar'),
                (CycleAnchor.anniversary, 'Card anniversary'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: current.anchor == anchor,
                  onSelected: linked
                      ? null
                      : (_) =>
                            _patch(current, (b) => b.copyWith(anchor: anchor)),
                ),
            ],
          ),
        ),
        // The window those two fields produce, live.
        if (cycle != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: Text(
              'This period runs ${formatDate(cycle.start, today)} – '
              '${formatDate(cycle.end, today)} (${cycle.label}).',
              style: note,
            ),
          ),
      ],
    );

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        if (linked && card != null) ...[
          Text(
            'The terms of this credit come from the catalogue and change '
            'when the issuer changes them. Enrolment, spend, tracking and '
            'reminders are yours.',
            style: note,
          ),
          const SizedBox(height: Space.s2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              key: const Key('change-terms'),
              onPressed: () => context.go(convertPath(card.id)),
              child: const Text('Change the terms'),
            ),
          ),
          const SizedBox(height: Space.s4),
        ],
        Text('Fields marked * are required.', style: note),
        const SizedBox(height: Space.s4),
        FieldGrid(
          fields: [
            field(
              'field-name',
              'Name',
              required: true,
              error: _nameError,
              controller: _name,
              focusNode: _nameFocus,
            ),
            field(
              'field-value',
              'Value each period',
              required: true,
              error: _valueError,
              controller: _value,
              focusNode: _valueFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            cadence,
            // A rolling credit measures from its last claim, not an anchor.
            if (current.cadence != Cadence.rolling) anchor,
            field(
              'field-ends-on',
              'Ends on (optional)',
              hint: 'The last day it can be used, if the issuer has set one.',
              error: _endsOnError,
              controller: _endsOn,
              focusNode: _endsOnFocus,
              keyboardType: TextInputType.datetime,
            ),
            DropdownButtonFormField<BenefitCategory>(
              key: const Key('field-category'),
              isExpanded: true,
              initialValue: current.category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final category in BenefitCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(categoryLabel(category)),
                  ),
              ],
              onChanged: linked
                  ? null
                  : (category) {
                      if (category != null) {
                        _patch(current, (b) => b.copyWith(category: category));
                      }
                    },
            ),
            field(
              'field-merchant',
              'Where it must be spent (optional)',
              hint: 'Used to spot the same credit sitting on two cards.',
              controller: _merchant,
              focusNode: _merchantFocus,
            ),
          ],
          wide: [
            SwitchRow(
              title: 'Needs enrolment',
              note:
                  'Until it is enrolled the credit is Locked, and never counted '
                  'as money you are failing to spend.',
              label: 'Needs enrolment',
              value: current.enrollmentRequired,
              onChanged: linked
                  ? null
                  : (next) => _patch(
                      current,
                      (b) => b.copyWith(enrollmentRequired: next),
                    ),
            ),
            if (current.enrollmentRequired) ...[
              SwitchRow(
                title: 'Enrolled',
                note: current.enrolledAt == null
                    ? 'Not yet — the credit is locked.'
                    : 'Confirmed '
                          '${formatDate(current.enrolledAt!.substring(0, 10), today)}.',
                label: 'Enrolled',
                value: current.enrolledAt != null,
                onChanged: (next) => next
                    ? store.confirmEnrollment(current.id)
                    : store.revokeEnrollment(current.id),
              ),
              field(
                'field-url',
                'Enrolment page (optional)',
                error: _urlError,
                controller: _url,
                focusNode: _urlFocus,
                keyboardType: TextInputType.url,
              ),
            ],
            field(
              'field-spend-threshold',
              'Unlocks after spending (optional)',
              hint:
                  'Dollars the issuer asks you to spend in a year before this '
                  'credit opens.',
              error: _spendError,
              controller: _spend,
              focusNode: _spendFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            if (current.spendThresholdCents != null)
              SwitchRow(
                title: 'Spend reached this year',
                note: current.spendMetAt == null
                    ? 'Not yet — the credit is locked.'
                    : 'Confirmed '
                          '${formatDate(current.spendMetAt!.substring(0, 10), today)}.',
                label: 'Spend reached this year',
                value: current.spendMetAt != null,
                onChanged: (next) => next
                    ? store.confirmSpend(current.id)
                    : store.revokeSpend(current.id),
              ),
            field(
              'field-steps',
              'How to redeem',
              hint: 'One step per line.',
              controller: _steps,
              focusNode: _stepsFocus,
              keyboardType: TextInputType.multiline,
              maxLines: null,
            ),
            SwitchRow(
              title: 'Track this credit',
              note:
                  'Turn off to keep its history without counting it or '
                  'reminding you.',
              label: 'Track this credit',
              value: current.active,
              onChanged: (next) =>
                  _patch(current, (b) => b.copyWith(active: next)),
            ),
            SwitchRow(
              title: 'Last call only',
              note: 'Skip the earlier rungs and warn once, at the end.',
              label: 'Last call only',
              value: current.lastCallOnly,
              onChanged: (next) =>
                  _patch(current, (b) => b.copyWith(lastCallOnly: next)),
            ),
            SwitchRow(
              title: 'Silence this credit',
              note: 'Keeps tracking it, sends nothing.',
              label: 'Silence this credit',
              value: store.isBenefitMuted(current.id),
              onChanged: (_) => store.toggleBenefitMute(current.id),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go(_home(current)),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}
