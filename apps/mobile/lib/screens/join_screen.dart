import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/screen_title.dart';

/// Joining a household with an invite, from a link (`/invite/<code>`) or a
/// code typed in. Leaving a household that holds cards asks first; a used,
/// expired or unknown code says so and stays.
class JoinScreen extends StatefulWidget {
  const JoinScreen({
    super.key,
    required this.store,
    required this.code,
    this.ui,
  });

  final AppStore store;
  final String code;
  final UiState? ui;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join({bool confirmLeave = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.store.joinHousehold(
      widget.code,
      confirmLeave: confirmLeave,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case JoinOutcome.joined:
        widget.ui?.snackbar.show('You joined the household.');
        context.go(Paths.today);
      case JoinOutcome.holdsCards:
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave your cards behind?'),
            content: const Text(
              'Your household holds cards. They stay with it, and you will '
              'not see them once you join. Anyone else in it keeps them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Leave and join'),
              ),
            ],
          ),
        );
        if (leave == true) await _join(confirmLeave: true);
      case JoinOutcome.used:
        setState(
          () => _error = 'This invite has been used. Ask for a new one.',
        );
      case JoinOutcome.expired:
        setState(
          () => _error =
              'This invite has expired. Invites last seven days; ask for a '
              'new one.',
        );
      case JoinOutcome.notFound:
        setState(() => _error = 'No invite has that code. Check the letters.');
      case JoinOutcome.ownerHasMembers:
        setState(
          () => _error =
              'You own a household with other people in it. Remove them '
              'first, or ask one of them to take it over.',
        );
      case JoinOutcome.alreadyMember:
        setState(() => _error = 'You are already in this household.');
      case JoinOutcome.offline:
        setState(() => _error = 'You are offline. Joining needs a connection.');
      case JoinOutcome.failed:
        setState(() => _error = 'That did not work. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Paths.today),
        ),
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
                  Icon(
                    Icons.group_add_outlined,
                    size: 48,
                    color: tokens.accent,
                  ),
                  const SizedBox(height: Space.s4),
                  ScreenTitle(
                    label: 'Join a household',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: Space.s2),
                  Text(
                    'You have been invited to share a household’s cards and '
                    'credits. Joining moves you out of your own.',
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
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
                  FilledButton(
                    key: const Key('join'),
                    onPressed: _busy ? null : _join,
                    child: const Text('Join this household'),
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
