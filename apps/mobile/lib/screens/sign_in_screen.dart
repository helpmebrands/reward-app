import 'package:flutter/material.dart';

import '../logic/session.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/screen_title.dart';

/// Sign-in: Google or Apple through Firebase, and nothing else. There is no
/// guest mode; the household lives in the service tier. "Learn more"
/// replays the welcome slideshow. When sign-in succeeds the router's
/// redirect leaves this screen.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.auth,
    required this.onLearnMore,
  });

  final AuthService auth;
  final VoidCallback onLearnMore;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn(Future<void> Function() attempt) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await attempt();
    } on SignInFailed catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Sign-in did not finish. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final error = _error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.savings_outlined, size: 48, color: tokens.accent),
                  const SizedBox(height: Space.s4),
                  ScreenTitle(
                    label: 'Sign in',
                    text: 'Sign in to HelpMe Reward',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: Space.s2),
                  Text(
                    'Your household’s cards and credits are kept with your '
                    'account, so everyone you share them with sees the same.',
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.s8),
                  FilledButton(
                    key: const Key('sign-in-google'),
                    onPressed: _busy
                        ? null
                        : () => _signIn(widget.auth.signInWithGoogle),
                    child: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: Space.s3),
                  OutlinedButton.icon(
                    key: const Key('sign-in-apple'),
                    onPressed: _busy
                        ? null
                        : () => _signIn(widget.auth.signInWithApple),
                    icon: const Icon(Icons.apple),
                    label: const Text('Continue with Apple'),
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
                  const SizedBox(height: Space.s6),
                  TextButton(
                    key: const Key('sign-in-learn-more'),
                    onPressed: widget.onLearnMore,
                    child: const Text('Learn more'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
