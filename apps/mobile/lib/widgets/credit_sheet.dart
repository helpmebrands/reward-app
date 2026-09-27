import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/credit_actions.dart';
import '../shell/router.dart';
import '../theme/nocturne_tokens.dart' hide Tone;
import 'notification_level_control.dart';
import 'value_bar.dart';

/// Quick amounts: a quarter and a half of what is left, rounded to whole
/// dollars because nobody logs $37.53, each at least a dollar and under the
/// remainder. Nothing under five dollars, where the buttons would be noise.
List<int> quickAmounts(int remainingCents) {
  if (remainingCents < 500) return const [];
  final candidates = [
    (remainingCents / 4 / 100).round() * 100,
    (remainingCents / 2 / 100).round() * 100,
  ].where((cents) => cents >= 100 && cents < remainingCents);
  return candidates.toSet().toList();
}

/// The credit detail sheet: the one place every credit action lives.
///
/// Its job is to make logging a *partial* amount as easy as logging the
/// whole thing. Most of these credits are spent in pieces, and an app that
/// only offers a tick mark quietly trains people to lie to it. It tracks a
/// benefit id and reads the instance from the store on every build, so the
/// balance follows a claim without reopening.
class CreditSheet extends StatelessWidget {
  const CreditSheet({
    super.key,
    required this.actions,
    required this.benefitId,
    required this.onClose,
  });

  /// The shared actions, so a sheet button does what a swipe does.
  final CreditActions actions;
  final String benefitId;
  final VoidCallback onClose;

  AppStore get store => actions.store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final instance = store.instanceFor(benefitId);
        if (instance == null) return _Gone(onClose: onClose);
        return _SheetBody(
          actions: actions,
          instance: instance,
          onClose: onClose,
        );
      },
    );
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Space.s6),
    child: Row(
      children: [
        const Expanded(child: Text('This credit is no longer tracked.')),
        _CloseButton(onClose: onClose),
      ],
    ),
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('sheet-close'),
    tooltip: 'Close',
    onPressed: onClose,
    icon: const Icon(Icons.close),
  );
}

class _SheetBody extends StatefulWidget {
  const _SheetBody({
    required this.actions,
    required this.instance,
    required this.onClose,
  });

  final CreditActions actions;
  final BenefitInstance instance;
  final VoidCallback onClose;

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  bool _custom = false;
  final TextEditingController _amount = TextEditingController();
  String? _amountError;

  BenefitInstance get instance => widget.instance;
  Benefit get benefit => instance.benefit;
  CreditActions get actions => widget.actions;
  AppStore get store => actions.store;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _log([int? amountCents]) {
    actions.log(instance, amountCents: amountCents);
    widget.onClose();
  }

  void _logCustom() {
    final cents = parseMoneyToCents(_amount.text);
    if (cents == null || cents == 0) {
      setState(() => _amountError = 'Enter an amount in dollars.');
      return;
    }
    // Never let a claim exceed what the cycle actually holds.
    _log(cents < instance.remainingCents ? cents : instance.remainingCents);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final status = instance.status;
    final breakdown = creditBreakdown(instance);
    final today = store.today;
    final manual = benefit.cadence == Cadence.manual;
    final rolling = benefit.cadence == Cadence.rolling;
    final claims = store.claimsFor(benefit.id, instance.cycle.key);
    // The deadline line under the meter, by what kind of window this is.
    final deadline = manual
        ? 'Tracked by hand — no deadline'
        : rolling
        ? status == BenefitStatus.captured
              ? 'Eligible again ${formatDate(addDays(instance.cycle.end, 1), today)}'
              : 'Eligible now — the clock restarts when you claim it'
        : instance.daysRemaining < 0
        ? 'Expired ${formatDate(instance.cycle.end, today)}'
        : '${formatDaysRemaining(instance.daysRemaining)} — closes '
              '${formatDate(instance.cycle.end, today)}';
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.s6,
        Space.s4,
        Space.s6,
        Space.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardLabel(instance.card).toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: tokens.accentRamp[400],
                      ),
                    ),
                    Semantics(
                      header: true,
                      child: Text(benefit.name, style: text.titleMedium),
                    ),
                    Text(
                      '${cadenceLabel(benefit.cadence)} · ${instance.cycle.label}'
                      '${manual || rolling ? '' : ' · ${formatRange(instance.cycle.start, instance.cycle.end, today)}'}'
                      '${benefit.endsOn == null ? '' : ' · ends ${formatDate(benefit.endsOn!, today)}'}',
                      style: note,
                    ),
                  ],
                ),
              ),
              _CloseButton(onClose: widget.onClose),
            ],
          ),
          const SizedBox(height: Space.s6),

          // Meter
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatMoney(instance.remainingCents),
                key: const Key('credit-sheet-balance'),
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Text(
                  'left of ${formatMoney(benefit.valueCents)}',
                  style: note,
                ),
              ),
            ],
          ),
          // The current window as earned, available or opt out; a
          // spend-gated credit has nothing to show until the spend is met.
          if (breakdown.totalCents > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s4),
              child: ValueBar(breakdown: breakdown),
            )
          else
            const SizedBox(height: Space.s4),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: tokens.accentRamp[300]),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Text(
                  deadline,
                  style: text.bodySmall?.copyWith(
                    color: tokens.accentRamp[300],
                  ),
                ),
              ),
            ],
          ),

          if (status == BenefitStatus.locked) ...[
            const SizedBox(height: Space.s6),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: tokens.locked.foreground,
                      ),
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: Text(
                          lockReason(benefit, instance.card, today) ==
                                  LockReason.spend
                              ? 'Unlocks after '
                                    '${formatMoney(benefit.spendThresholdCents ?? 0)} '
                                    'spend this year.'
                              : benefit.enrollmentNote ??
                                    'Not enrolled. ${formatMoney(benefit.valueCents)} is '
                                        'unreachable until you tick the box on the issuer’s '
                                        'benefits page.',
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s4),
                  if (!store.canWrite)
                    const SizedBox.shrink()
                  else if (lockReason(benefit, instance.card, today) ==
                      LockReason.spend)
                    OutlinedButton(
                      onPressed: () => actions.confirmSpend(instance),
                      child: const Text('I’ve reached it — unlock'),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => actions.confirmEnrollment(instance),
                      child: const Text('I’ve enrolled — unlock this credit'),
                    ),
                ],
              ),
            ),
          ],

          if (store.canWrite &&
              (status == BenefitStatus.useSoon ||
                  status == BenefitStatus.available)) ...[
            const SizedBox(height: Space.s8),
            const _SectionTitle('Log what you spent'),
            Text(
              'Partial use is normal — log the dollars, not a tick.',
              style: note,
            ),
            const SizedBox(height: Space.s3),
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [
                for (final cents in quickAmounts(instance.remainingCents))
                  OutlinedButton(
                    onPressed: () => _log(cents),
                    child: Text(formatMoney(cents)),
                  ),
                OutlinedButton(
                  onPressed: () => setState(() => _custom = !_custom),
                  child: const Text('Other…'),
                ),
              ],
            ),
            if (_custom) ...[
              const SizedBox(height: Space.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('custom-amount'),
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount used, in dollars',
                        prefixText: '\$ ',
                        errorText: _amountError,
                      ),
                      onSubmitted: (_) => _logCustom(),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  OutlinedButton(
                    onPressed: _logCustom,
                    child: const Text('Log'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Space.s3),
            OutlinedButton(
              onPressed: () => _log(),
              child: Text(
                'Mark the full ${formatMoney(instance.remainingCents)} used',
              ),
            ),
          ],

          // Undo without a clock: every claim this period can be taken back
          // here, long after any snackbar has gone.
          if (claims.isNotEmpty) ...[
            const SizedBox(height: Space.s8),
            const _SectionTitle('Logged this period'),
            Column(
              key: const Key('sheet-claims'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final claim in claims)
                  Padding(
                    key: ValueKey('sheet-claim-${claim.id}'),
                    padding: const EdgeInsets.symmetric(vertical: Space.s1),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: formatMoney(claim.amountCents)),
                                TextSpan(
                                  text:
                                      ' · ${formatDate(claim.claimedAt.substring(0, 10), today)}'
                                      '${claim.note != null ? ' · ${claim.note}' : ''}',
                                  style: note,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (store.isPending(claim.id))
                          Padding(
                            padding: const EdgeInsets.only(right: Space.s2),
                            child: Text('Pending', style: note),
                          ),
                        if (store.canWrite)
                          OutlinedButton(
                            onPressed: () =>
                                actions.removeClaim(instance, claim),
                            child: Text(
                              'Remove',
                              semanticsLabel:
                                  'Remove the ${formatMoney(claim.amountCents)} logged on '
                                  '${formatDate(claim.claimedAt.substring(0, 10), today)}',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          if (status == BenefitStatus.captured) ...[
            const SizedBox(height: Space.s6),
            _Panel(
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 19, color: tokens.accent),
                  const SizedBox(width: Space.s3),
                  const Expanded(
                    child: Text(
                      'Fully captured. Reminders stay off until it resets.',
                    ),
                  ),
                  if (store.canWrite)
                    OutlinedButton(
                      onPressed: () => actions.unclaimAll(instance),
                      child: const Text('Undo'),
                    ),
                ],
              ),
            ),
          ],

          if (status == BenefitStatus.missed) ...[
            const SizedBox(height: Space.s6),
            _Panel(
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_bottom,
                    size: 17,
                    color: tokens.missed.foreground,
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Text(
                      'This window closed on ${formatDate(instance.cycle.end, today)} '
                      'with ${formatMoney(instance.remainingCents)} unused. It does not roll over.',
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (benefit.redemptionSteps.isNotEmpty) ...[
            const SizedBox(height: Space.s8),
            const _SectionTitle('How to redeem'),
            for (final (index, step) in benefit.redemptionSteps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: Space.s8,
                      child: Text(
                        '${index + 1}',
                        style: text.bodySmall?.copyWith(color: tokens.accent),
                      ),
                    ),
                    Expanded(child: Text(step, style: text.bodySmall)),
                  ],
                ),
              ),
          ],

          if (benefit.notes != null) ...[
            const SizedBox(height: Space.s6),
            _Panel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: tokens.neutral[500],
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(child: Text(benefit.notes!, style: note)),
                ],
              ),
            ),
          ],

          const SizedBox(height: Space.s8),
          NotificationLevelControl(
            benefit: benefit,
            level: store.notificationLevel(benefit.id),
            cardMuted: store.isCardMuted(benefit.cardId),
            onChanged: store.isMutePending(benefit.id)
                ? null
                : (level) => actions.setLevel(instance, level),
          ),
          const SizedBox(height: Space.s6),
          if (store.canWrite)
            TextButton.icon(
              onPressed: () {
                widget.onClose();
                actions.optOut(instance);
              },
              icon: const Icon(Icons.do_not_disturb_on_outlined, size: 14),
              label: const Text('Opt out — I won\'t use this'),
            ),
          if (store.canWrite)
            TextButton.icon(
              onPressed: () {
                widget.onClose();
                context.go(benefitPath(benefit.id));
              },
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Edit this credit'),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s2),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: tokens.surfaceQuiet,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: child,
    );
  }
}
