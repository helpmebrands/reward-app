import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart' hide Tone;

/// An in-app preview of the next reminder.
///
/// Reminders are the app's whole reason to exist, and most people will not
/// grant notification permission on faith. Showing exactly what one looks
/// like, with the user's own numbers, is the honest way to ask. It leaves on
/// its own after six seconds, on Dismiss, or on a tap that opens it.
class NudgePreview extends StatefulWidget {
  const NudgePreview({
    super.key,
    required this.reminder,
    required this.onDismiss,
    required this.onOpen,
  });

  final Reminder reminder;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  @override
  State<NudgePreview> createState() => _NudgePreviewState();
}

class _NudgePreviewState extends State<NudgePreview> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 6), widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final reminder = widget.reminder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, 0),
      child: Material(
        key: const Key('nudge-preview'),
        color: tokens.surfaceRaised,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(Radii.lg)),
          side: BorderSide(color: tokens.surfaceLine),
        ),
        child: Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: widget.onOpen,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(Radii.lg),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          reminder.tone == Tone.urgent
                              ? Icons.warning_amber
                              : Icons.hourglass_top,
                          size: 18,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: Space.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(text: 'HelpMe Reward'),
                                    TextSpan(
                                      text: '  preview',
                                      style: TextStyle(
                                        color: tokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                style: text.labelSmall,
                              ),
                              Text(
                                reminder.title,
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                reminder.body,
                                style: text.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              MergeSemantics(
                child: Semantics(
                  label: 'Dismiss preview',
                  child: IconButton(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A stand-in used when nothing is actually scheduled yet.
Reminder sampleReminder(int claimableCents, DateTime now) => Reminder(
  id: 'preview',
  fireAt: now.millisecondsSinceEpoch,
  tag: 'preview',
  url: '/',
  tone: Tone.notice,
  totalCents: claimableCents,
  items: const [],
  title: claimableCents > 0
      ? '${formatMoney(claimableCents)} on the line — one week left'
      : 'Nothing expiring yet',
  body: claimableCents > 0
      ? 'This is the shape of the nudge: one alert for the day, leading with the credit you stand to lose most on.'
      : 'Add a card and this is where the week-out warning will appear.',
);
