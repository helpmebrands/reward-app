import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/nocturne_tokens.dart';
import 'swipe_row.dart';

/// Which of the five tones a row is drawn in. Every status maps to one, so a
/// row's colour is always a token and never a hex.
enum RowTone { soon, available, locked, captured, missed }

RowTone toneFor(BenefitStatus status) => switch (status) {
  BenefitStatus.useSoon => RowTone.soon,
  BenefitStatus.available => RowTone.available,
  BenefitStatus.locked => RowTone.locked,
  BenefitStatus.captured || BenefitStatus.manual => RowTone.captured,
  BenefitStatus.missed => RowTone.missed,
};

/// One credit in a list: its name, its cadence, window and holder, and the
/// money at stake with the deadline.
///
/// Every row is reachable three ways: tap to open the detail sheet, swipe
/// right to log the whole credit, swipe left to silence it. The swipe is an
/// accelerator, because a gesture nobody discovers is not a feature: the bell
/// silences by name, the sheet carries the same actions, and each is a
/// semantics action a screen reader and a switch can reach. A row without
/// callbacks is static, as Today drew it before the actions arrived.
class CreditRow extends StatelessWidget {
  const CreditRow({
    super.key,
    required this.instance,
    this.showCard = false,
    this.onOpen,
    this.onLogAll,
    this.onToggleMute,
  });

  final BenefitInstance instance;

  /// Shows the holder in the subtitle. Off inside a per-card group.
  final bool showCard;

  /// Opens the credit sheet.
  final VoidCallback? onOpen;

  /// Logs the whole remaining balance.
  final VoidCallback? onLogAll;

  /// Silences or unsilences the credit.
  final VoidCallback? onToggleMute;

  RowTone get tone => toneFor(instance.status);

  bool get claimable =>
      instance.status == BenefitStatus.useSoon ||
      instance.status == BenefitStatus.available;

  String get subtitle {
    final parts = [
      cadenceLabel(instance.benefit.cadence),
      instance.cycle.label,
    ];
    // The holder, not the full card name: two identical Platinums differ only
    // by who holds them.
    if (showCard) {
      parts.add(
        instance.card.holder.isNotEmpty
            ? instance.card.holder
            : cardLabel(instance.card),
      );
    }
    return parts.join(' · ');
  }

  String get deadline {
    final status = instance.status;
    if (status == BenefitStatus.manual) return 'No deadline';
    if (status == BenefitStatus.captured) return 'Captured';
    // A rolling credit's clock starts only when it is claimed.
    if (instance.benefit.cadence == Cadence.rolling) return 'Eligible now';
    if (instance.daysRemaining < 0) return 'Expired';
    return formatDaysRemaining(instance.daysRemaining);
  }

  String get amount => formatMoney(
    instance.status == BenefitStatus.captured
        ? instance.claimedCents
        : instance.remainingCents,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final palette = switch (tone) {
      RowTone.soon => tokens.soon,
      RowTone.available => tokens.available,
      RowTone.locked => tokens.locked,
      RowTone.captured => tokens.captured,
      RowTone.missed => tokens.missed,
    };
    final text = Theme.of(context).textTheme;
    final muted = instance.muted;
    final name = instance.benefit.name;
    final logAll = onLogAll;
    final logAction = claimable ? logAll : null;
    final toggleMute = onToggleMute;

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The name wraps rather than ellipsises: at a large text
                // size a truncated name loses the one thing the row is for.
                Text(
                  name,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: text.bodyMedium?.copyWith(color: palette.foreground),
              ),
              Text(
                deadline,
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );

    final card = Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: palette.ground,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        border: Border.all(color: palette.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Expanded(
              child: onOpen == null
                  ? body
                  : InkWell(
                      onTap: onOpen,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(Radii.md),
                      ),
                      child: body,
                    ),
            ),
            if (toggleMute != null)
              Padding(
                padding: const EdgeInsets.only(right: Space.s1),
                // The row's own title is not enough context in a long list,
                // so the credit is named in the label.
                child: MergeSemantics(
                  child: Semantics(
                    label:
                        '${muted ? 'Unsilence' : 'Silence'} reminders for $name',
                    toggled: muted,
                    child: IconButton(
                      onPressed: toggleMute,
                      color: muted ? tokens.accent : tokens.textSecondary,
                      icon: Icon(
                        muted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label: instance.status == BenefitStatus.locked
          ? statusLabel(BenefitStatus.locked)
          : null,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Log the full credit'): ?logAction,
        CustomSemanticsAction(label: muted ? 'Unsilence' : 'Silence'):
            ?toggleMute,
      },
      child: SwipeRow(
        // Nothing to log and nothing to silence on a captured or untracked
        // row; a locked row can still be silenced.
        disabled:
            (logAll == null && toggleMute == null) ||
            (!claimable && instance.status != BenefitStatus.locked),
        leading: logAll == null || !claimable
            ? null
            : SwipeAction(
                label: 'Log it',
                icon: Icons.check_circle,
                tone: SwipeTone.accent,
                onAct: logAll,
              ),
        trailing: toggleMute == null
            ? null
            : SwipeAction(
                label: muted ? 'Unmute' : 'Silence',
                icon: muted
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                tone: SwipeTone.quiet,
                onAct: toggleMute,
              ),
        child: card,
      ),
    );
  }
}
