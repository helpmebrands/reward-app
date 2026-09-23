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

String networkLabel(CardNetwork network) => switch (network) {
  CardNetwork.amex => 'American Express',
  CardNetwork.visa => 'Visa',
  CardNetwork.mastercard => 'Mastercard',
  CardNetwork.discover => 'Discover',
  CardNetwork.other => 'Other',
};

/// Editing a card: its details, and the list of credits attached to it.
///
/// Fields write the store as soon as their value is valid, as the PWA's
/// editors do; what was typed is kept apart in a draft, so an invalid value
/// shows its error without being written or snapped back. Back asks only
/// while a field still holds such a value.
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({
    super.key,
    required this.store,
    required this.id,
    this.ui,
  });

  final AppStore store;
  final String id;
  final UiState? ui;

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  final _holder = TextEditingController();
  final _nickname = TextEditingController();
  final _fee = TextEditingController();
  final _anniversary = TextEditingController();
  final _holderFocus = FocusNode(debugLabel: 'holder');
  final _nicknameFocus = FocusNode(debugLabel: 'nickname');
  final _feeFocus = FocusNode(debugLabel: 'fee');
  final _anniversaryFocus = FocusNode(debugLabel: 'anniversary');

  AppStore get store => widget.store;

  Card? get card {
    for (final c in store.data?.cards ?? const <Card>[]) {
      if (c.id == widget.id) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final current = card;
    if (current != null) {
      _holder.text = current.holder;
      _nickname.text = current.nickname ?? '';
      _fee.text = (current.annualFeeCents / 100).toString();
      _anniversary.text = current.anniversaryOn;
    }
    for (final c in [_holder, _nickname, _fee, _anniversary]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_holder, _nickname, _fee, _anniversary]) {
      c.dispose();
    }
    for (final f in [
      _holderFocus,
      _nicknameFocus,
      _feeFocus,
      _anniversaryFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  String? get _holderError =>
      requiredError(_holder.text, 'Enter whose card this is.');
  String? get _feeError => moneyError(_fee.text);
  String? get _anniversaryError => anniversaryError(_anniversary.text);
  bool get _unsaved =>
      _holderError != null || _feeError != null || _anniversaryError != null;

  /// Writes every valid draft; the invalid ones wait, showing their error.
  void _changed() {
    final current = card;
    if (current == null) return;
    final holder = _holder.text.trim();
    final nickname = _nickname.text.trim();
    final cents = parseMoney(_fee.text);
    final anniversary = _anniversary.text;
    final patch = <Card Function(Card)>[
      if (_holderError == null && holder != current.holder)
        (c) => c.copyWith(holder: holder),
      if ((current.nickname ?? '') != nickname)
        (c) => c.copyWith(nickname: nickname.isEmpty ? null : nickname),
      if (cents != null && cents >= 0 && cents != current.annualFeeCents)
        (c) => c.copyWith(annualFeeCents: cents),
      if (_anniversaryError == null && anniversary != current.anniversaryOn)
        (c) => c.copyWith(anniversaryOn: anniversary),
    ];
    if (patch.isNotEmpty) {
      store.updateCard(current.id, (c) => patch.fold(c, (c, p) => p(c)));
    }
    setState(() {});
  }

  void _leave() => context.go(Paths.cards);

  Future<void> _back() async {
    if (!_unsaved || await confirmLeave(context)) {
      if (mounted) _leave();
    }
  }

  Future<void> _delete() async {
    final current = card;
    if (current == null) return;
    // Deleting a card destroys its claim history, which no undo snackbar can
    // honestly cover, so this one asks first.
    if (!await confirmDelete(context, cardLabel(current))) return;
    await store.deleteCard(current.id);
    widget.ui?.snackbar.show('Card deleted.');
    if (mounted) _leave();
  }

  Future<void> _addBenefit() async {
    final current = card;
    if (current == null) return;
    final benefit = await store.addBenefit(
      Benefit(
        id: '',
        cardId: current.id,
        name: 'New credit',
        category: BenefitCategory.other,
        valueCents: 0,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: false,
        redemptionSteps: const [],
        muted: false,
        lastCallOnly: false,
        active: true,
        createdAt: '',
        updatedAt: '',
      ),
    );
    if (mounted) context.go(benefitPath(benefit.id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final current = card;
        if (current == null) {
          return EditorScaffold(
            title: 'Card not found',
            onBack: _leave,
            snackbar: widget.ui?.snackbar,
            child: const NotFoundBody('That card is no longer here.'),
          );
        }
        final benefits =
            store.data!.benefits.where((b) => b.cardId == current.id).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: EditorScaffold(
            title: cardLabel(current),
            subtitle:
                '${benefits.length} credit${benefits.length == 1 ? '' : 's'}',
            onBack: _back,
            action: EditorAction(
              icon: Icons.delete_outline,
              label: 'Delete this card',
              onAct: _delete,
            ),
            snackbar: widget.ui?.snackbar,
            child: Builder(
              builder: (context) => _form(context, current, benefits),
            ),
          ),
        );
      },
    );
  }

  Widget _form(BuildContext context, Card current, List<Benefit> benefits) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);

    Widget field(
      String key,
      String label, {
      String? hint,
      String? error,
      required TextEditingController controller,
      required FocusNode focusNode,
      bool required = false,
      TextInputType? keyboardType,
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
        decoration: control.decoration,
      ),
    );

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        Text('Fields marked * are required.', style: note),
        const SizedBox(height: Space.s4),
        FieldGrid(
          fields: [
            field(
              'field-holder',
              'Cardholder',
              required: true,
              error: _holderError,
              controller: _holder,
              focusNode: _holderFocus,
            ),
            field(
              'field-nickname',
              'Nickname',
              hint: '${current.issuer} ${current.product} when blank.',
              controller: _nickname,
              focusNode: _nicknameFocus,
            ),
            field(
              'field-fee',
              'Annual fee',
              required: true,
              error: _feeError,
              controller: _fee,
              focusNode: _feeFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            field(
              'field-anniversary',
              'Renews on',
              required: true,
              error: _anniversaryError,
              controller: _anniversary,
              focusNode: _anniversaryFocus,
              keyboardType: TextInputType.datetime,
            ),
            DropdownButtonFormField<CardNetwork>(
              key: const Key('field-network'),
              isExpanded: true,
              initialValue: current.network,
              decoration: const InputDecoration(labelText: 'Network'),
              items: [
                for (final network in CardNetwork.values)
                  DropdownMenuItem(
                    value: network,
                    child: Text(networkLabel(network)),
                  ),
              ],
              onChanged: (network) {
                if (network != null) {
                  store.updateCard(
                    current.id,
                    (c) => c.copyWith(network: network),
                  );
                }
              },
            ),
          ],
          wide: [
            SwitchRow(
              title: 'Silence every credit',
              note: 'Keeps tracking them, sends nothing.',
              label: 'Silence every credit',
              value: current.muted,
              onChanged: (_) => store.toggleCardMute(current.id),
            ),
            SwitchRow(
              title: 'Archive this card',
              note: 'Hides it everywhere and keeps its history.',
              label: 'Archive this card',
              value: current.archived,
              onChanged: (next) => store.updateCard(
                current.id,
                (c) => c.copyWith(archived: next),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Credits', style: text.titleSmall),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addBenefit,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: Space.s3),
        for (final benefit in benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: _BenefitLink(
              key: ValueKey('benefit-link-${benefit.id}'),
              benefit: benefit,
              onTap: () => context.go(benefitPath(benefit.id)),
            ),
          ),
      ],
    );
  }
}

class _BenefitLink extends StatelessWidget {
  const _BenefitLink({super.key, required this.benefit, required this.onTap});

  final Benefit benefit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final meta = [
      cadenceLabel(benefit.cadence),
      formatMoney(benefit.valueCents),
      if (isLocked(benefit)) 'needs enrolment',
      if (!benefit.active) 'paused',
    ].join(' · ');
    return Material(
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: tokens.surfaceLine),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 15, color: tokens.accent),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(benefit.name, style: text.bodyMedium),
                    Text(
                      meta,
                      style: text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
