import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/household_api.dart';
import '../logic/app_store.dart';
import '../logic/ui_state.dart';
import '../shell/brand_app_bar.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/brand_logo.dart';
import '../widgets/screen_title.dart';

/// Accepting an invite, from a link (`/invite/<code>`) or a code typed in.
/// It reads the invite first and says whose cards it shares, all of them or
/// how many, and at which access; a used, expired, unknown, own or
/// already-shared code says so and stays. Accepting moves and deletes
/// nothing of yours.
///
/// Reached from a link, so it carries the brand: the lockup in the bar
/// instead of Back and a title, and the two-line logo above the message.
class JoinScreen extends StatefulWidget {
  const JoinScreen({
    super.key,
    required this.store,
    required this.code,
    this.ui,
    this.showSettings = false,
  });

  final AppStore store;
  final String code;
  final UiState? ui;

  /// The gear in the bar, shown only when signed in.
  final bool showSettings;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

/// Why an invite cannot be read or accepted, as the join screen says it.
/// [owner] names the person who shares, once the invite has been read.
String joinProblem(JoinOutcome outcome, {String? owner}) => switch (outcome) {
  JoinOutcome.used => 'This invite has been used. Ask for a new one.',
  JoinOutcome.expired =>
    'This invite has expired. Invites last seven days; ask for a new one.',
  JoinOutcome.notFound => 'No invite has that code. Check the letters.',
  JoinOutcome.ownInvite =>
    'This is your own invite. Send it to the person you want to share with.',
  JoinOutcome.alreadyShared =>
    '${owner ?? 'This person'} already shares cards with you. Ask them to '
        'change what you see instead.',
  JoinOutcome.offline => 'You are offline. Accepting needs a connection.',
  JoinOutcome.accepted || JoinOutcome.failed => 'That did not work. Try again.',
};

/// "Alex wants to share all their cards with you." or "… 2 of their cards
/// …".
String offerHeadline(InviteOffer offer) {
  final who = offer.owner.displayName;
  final count = offer.cardCount ?? 0;
  final cards = offer.allCards
      ? 'all their cards'
      : '$count of their card${count == 1 ? '' : 's'}';
  return '$who wants to share $cards with you.';
}

/// What accepting lets you do with the cards.
String offerAccess(InviteOffer offer) => offer.access == CardAccess.view
    ? 'You’ll be able to view them.'
    : 'You’ll be able to view them and record what you use.';

class _JoinScreenState extends State<JoinScreen> {
  InviteOffer? _offer;
  bool _reading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final (:offer, :problem) = await widget.store.readInvite(widget.code);
    if (!mounted) return;
    setState(() {
      _reading = false;
      _offer = offer;
      _error = problem == null ? null : joinProblem(problem);
    });
  }

  Future<void> _accept() async {
    final owner = _offer?.owner.displayName;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.store.acceptInvite(widget.code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == JoinOutcome.accepted) {
      widget.ui?.snackbar.show('You can see $owner’s cards now.');
      context.go(Paths.today);
      return;
    }
    setState(() => _error = joinProblem(outcome, owner: owner));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final error = _error;
    final offer = _offer;
    return Scaffold(
      appBar: BrandAppBar(
        widthClass: WidthClass.forWidth(MediaQuery.sizeOf(context).width),
        onSettings: widget.showSettings
            ? () => context.push(Paths.settings)
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo()),
                  const SizedBox(height: Space.s6),
                  ScreenTitle(
                    label: 'Accept an invite',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: Space.s2),
                  if (_reading)
                    const Center(child: CircularProgressIndicator())
                  else if (offer != null) ...[
                    Text(offerHeadline(offer), style: text.bodyLarge),
                    const SizedBox(height: Space.s1),
                    Text(
                      offerAccess(offer),
                      style: text.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      'Your own cards stay as they are.',
                      style: text.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.s6),
                  Semantics(
                    label: 'Invite code ${widget.code.split('').join(' ')}',
                    child: ExcludeSemantics(
                      child: Text(
                        widget.code,
                        textAlign: TextAlign.center,
                        style: text.headlineMedium?.copyWith(letterSpacing: 4),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s6),
                  // An invite that cannot be read has nothing to accept.
                  if (offer != null)
                    FilledButton(
                      key: const Key('accept'),
                      onPressed: _busy ? null : _accept,
                      child: const Text('Accept'),
                    ),
                  // The bar has no Back, so the way out is here.
                  const SizedBox(height: Space.s2),
                  TextButton(
                    onPressed: () => context.go(Paths.today),
                    child: const Text('Not now'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: Space.s4),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: text.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for an invite code and returns it in capitals, or null.
Future<String?> askForInviteCode(BuildContext context) async {
  final code = await showDialog<String>(
    context: context,
    builder: (context) => const _InviteCodeDialog(),
  );
  final trimmed = code?.trim().toUpperCase() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Owns its text controller, so it lives as long as the dialog does,
/// closing animation included.
class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog();

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Have an invite code?'),
    content: TextField(
      key: const Key('invite-code-field'),
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(labelText: 'Invite code'),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Continue'),
      ),
    ],
  );
}
