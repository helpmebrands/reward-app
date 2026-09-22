import 'package:flutter/material.dart';

import '../logic/snackbar_state.dart';
import '../theme/nocturne_tokens.dart';

/// Draws the current snackbar over [child], at the bottom of whatever
/// [child] fills. The shell puts it inside the content column, so from
/// medium it centres on the column the rail pushes off centre, and above
/// the navigation bar so it never covers the destination tapped next.
class SnackbarHost extends StatefulWidget {
  const SnackbarHost({super.key, required this.snackbar, required this.child});

  final SnackbarState snackbar;
  final Widget child;

  @override
  State<SnackbarHost> createState() => _SnackbarHostState();
}

class _SnackbarHostState extends State<SnackbarHost> {
  @override
  void initState() {
    super.initState();
    // A message that was waiting for a host gets its clock back.
    widget.snackbar.resume();
  }

  @override
  void dispose() {
    // A message with nothing to draw it has no clock: the host outlives
    // every screen in the app, and a test that tears the tree down must not
    // leave a timer behind. Paused rather than dismissed, since notifying
    // mid-unmount is not allowed.
    widget.snackbar.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snackbar = widget.snackbar;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ListenableBuilder(
          listenable: snackbar,
          builder: (context, _) {
            final message = snackbar.current;
            if (message == null) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.bottomCenter,
              child: _Snackbar(
                key: ValueKey(message.id),
                message: message,
                snackbar: snackbar,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Snackbar extends StatelessWidget {
  const _Snackbar({super.key, required this.message, required this.snackbar});

  final SnackbarMessage message;
  final SnackbarState snackbar;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final action = message.action;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s6),
      child: MouseRegion(
        onEnter: (_) => snackbar.pause(),
        onExit: (_) => snackbar.resume(),
        child: Focus(
          // A focus scope around the whole bar, so focus landing on Undo
          // pauses the clock and leaving it restarts the full duration.
          skipTraversal: true,
          canRequestFocus: false,
          onFocusChange: (focused) =>
              focused ? snackbar.pause() : snackbar.resume(),
          child: Material(
            key: const Key('snackbar'),
            color: tokens.neutral[900],
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
              side: BorderSide(color: tokens.neutral[800]!),
            ),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s6,
                Space.s3,
                Space.s3,
                Space.s3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message.text,
                        style: text.bodyMedium?.copyWith(
                          color: tokens.neutral[200],
                        ),
                      ),
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(width: Space.s3),
                    TextButton(
                      key: const Key('snackbar-action'),
                      style: TextButton.styleFrom(
                        foregroundColor: tokens.accentRamp[300],
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () {
                        action.onAct();
                        snackbar.dismiss();
                      },
                      child: Text(
                        action.label,
                        semanticsLabel: action.semanticsLabel,
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
