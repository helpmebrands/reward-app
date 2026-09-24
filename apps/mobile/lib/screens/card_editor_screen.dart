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
  final _label = TextEditingController();
  final _fee = TextEditingController();
  final _anniversary = TextEditingController();
  final _labelFocus = FocusNode(debugLabel: 'label');
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
      _label.text = current.label ?? '';
      _fee.text = (current.annualFeeCents / 100).toString();
      _anniversary.text = current.anniversaryOn;
    }
    for (final c in [_label, _fee, _anniversary]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_label, _fee, _anniversary]) {
      c.dispose();
    }
    for (final f in [_labelFocus, _feeFocus, _anniversaryFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  String? get _labelError {
    final current = card;
    if (current == null) return null;
    return labelError(
      _label.text,
      cards: store.data?.cards ?? const [],
      issuer: current.issuer,
      product: current.product,
      cardId: current.id,
    );
  }

  String? get _feeError => moneyError(_fee.text);
  String? get _anniversaryError => anniversaryError(_anniversary.text);
  bool get _unsaved =>
      _labelError != null || _feeError != null || _anniversaryError != null;

  /// Writes every valid draft; the invalid ones wait, showing their error.
  void _changed() {
    final current = card;
    if (current == null) return;
    final label = _label.text.trim();
    final cents = parseMoney(_fee.text);
    final anniversary = _anniversary.text;
    final patch = <Card Function(Card)>[
      if (_labelError == null && (current.label ?? '') != label)
        (c) => c.copyWith(label: label.isEmpty ? null : label),
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
              'field-label',
              'Label',
              hint:
                  '${productName(current.issuer, current.product)} when blank.',
              error: _labelError,
              controller: _label,
              focusNode: _labelFocus,
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
            KindChoice(
              kind: current.kind,
              onChanged: (kind) =>
                  store.updateCard(current.id, (c) => c.copyWith(kind: kind)),
            ),
          ],
          wide: [
            SwitchRow(
              title: 'Silence every credit',
              note: 'Keeps tracking them, sends nothing.',
              label: 'Silence every credit',
              value: store.isCardMuted(current.id),
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
              lock: switch (lockReason(benefit, current, store.today)) {
                LockReason.enrollment => 'needs enrolment',
                LockReason.spend => 'needs spend',
                null => null,
              },
              onTap: () => context.go(benefitPath(benefit.id)),
            ),
          ),
      ],
    );
  }
}

/// Personal or business, as two choice chips. Classification only: business
/// cards are marked on the Cards screen and nothing else changes yet.
class KindChoice extends StatelessWidget {
  const KindChoice({super.key, required this.kind, required this.onChanged});

  final CardKind kind;
  final ValueChanged<CardKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final note = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Kind', style: note),
        const SizedBox(height: Space.s2),
        Semantics(
          label: 'Kind',
          container: true,
          explicitChildNodes: true,
          child: Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final (value, label) in const [
                (CardKind.personal, 'Personal'),
                (CardKind.business, 'Business'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: kind == value,
                  onSelected: (_) => onChanged(value),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s1),
          child: Text(
            'Business cards are marked on the Cards screen.',
            style: note,
          ),
        ),
      ],
    );
  }
}

class _BenefitLink extends StatelessWidget {
  const _BenefitLink({
    super.key,
    required this.benefit,
    required this.lock,
    required this.onTap,
  });

  final Benefit benefit;

  /// What keeps the credit locked, for the meta line, or null when nothing.
  final String? lock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final meta = [
      cadenceLabel(benefit.cadence),
      formatMoney(benefit.valueCents),
      ?lock,
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
