import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';
import 'screen_title.dart';

/// The eyebrow over Today's number: the date and what the number counts.
String todayEyebrow(IsoDate today) =>
    '${formatHeaderDate(today).replaceAll(',', '').toUpperCase()}'
    ' · UNCLAIMED, OPEN PERIODS';

/// The line under Today's number: how many credits are open across how many
/// cards, and when the nearest window shuts.
String todayHeadlineSub({
  required int open,
  required int cards,
  IsoDate? resetOn,
}) {
  if (open == 0) {
    return 'Nothing is waiting on you. Every open credit is used.';
  }
  final soonest = resetOn != null
      ? ' The nearest window shuts ${formatResetDate(resetOn)}.'
      : '';
  return '$open open credit${open == 1 ? '' : 's'} across '
      '$cards card${cards == 1 ? '' : 's'}.$soonest';
}

/// Today's headline: the eyebrow, the claimable total and the line under it.
///
/// On Today the eyebrow is the screen's `ScreenTitle`, read as "Today"; with
/// [heading] false it is plain text, as the welcome slide draws it.
class TodayHeadline extends StatelessWidget {
  const TodayHeadline({
    super.key,
    required this.eyebrow,
    required this.claimableCents,
    required this.sub,
    this.heading = true,
  });

  final String eyebrow;
  final int claimableCents;
  final String sub;
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final parts = moneyParts(claimableCents);
    final eyebrowStyle = text.labelSmall?.copyWith(color: tokens.textSecondary);
    return Column(
      key: const Key('today-headline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The heading reads "Today"; the date and the eyebrow are what
        // is drawn, since the brand now sits in the bar above.
        if (heading)
          ScreenTitle(label: 'Today', text: eyebrow, style: eyebrowStyle)
        else
          Text(eyebrow, style: eyebrowStyle),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(parts.symbol, style: text.headlineSmall),
            // The number shrinks with the column rather than forcing a
            // sideways scroll, as the PWA's clamp() does.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  parts.digits,
                  key: const Key('today-amount'),
                  style: text.displayMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          sub,
          style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}
