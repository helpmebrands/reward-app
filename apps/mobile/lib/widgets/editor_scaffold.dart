import 'package:flutter/material.dart';

import '../logic/snackbar_state.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import 'screen_title.dart';
import 'snackbar_host.dart';

/// The frame of a full-screen editor: the app bar with a title, a subtitle,
/// a Back and an optional trailing action, the width class computed from the
/// window since the route sits outside the shell, the centred column, and
/// the snackbar hosted here for the same reason.
class EditorScaffold extends StatelessWidget {
  const EditorScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.onBack,
    this.action,
    this.snackbar,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final EditorAction? action;
  final SnackbarState? snackbar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final widthClass = WidthClass.forWidth(MediaQuery.sizeOf(context).width);
    final action = this.action;
    final body = WidthClassScope(
      widthClass: widthClass,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widthClass.column),
          child: child,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenTitle(label: title),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (action != null)
            MergeSemantics(
              child: Semantics(
                label: action.label,
                child: IconButton(
                  icon: Icon(action.icon),
                  onPressed: action.onAct,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: snackbar == null
            ? body
            : SnackbarHost(snackbar: snackbar!, child: body),
      ),
    );
  }
}

/// A trailing action on an editor's app bar, such as delete.
class EditorAction {
  const EditorAction({
    required this.icon,
    required this.label,
    required this.onAct,
  });

  final IconData icon;
  final String label;
  final VoidCallback onAct;
}

/// Short fields two to a row from expanded, one per row otherwise; the
/// PWA's `form-grid`. Wide items (panels, sections, buttons) take a row.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.fields, this.wide = const []});

  final List<Widget> fields;
  final List<Widget> wide;

  @override
  Widget build(BuildContext context) {
    final paired = WidthClass.of(context) == WidthClass.expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (paired)
          for (var i = 0; i < fields.length; i += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fields[i]),
                const SizedBox(width: Space.s8),
                Expanded(
                  child: i + 1 < fields.length
                      ? fields[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: Space.s6),
          ]
        else
          for (final f in fields) ...[f, const SizedBox(height: Space.s6)],
        for (final w in wide) ...[w, const SizedBox(height: Space.s4)],
      ],
    );
  }
}

/// A gone entity: the not-found state of an editor.
class NotFoundBody extends StatelessWidget {
  const NotFoundBody(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    return Padding(
      padding: EdgeInsets.all(WidthClass.of(context).padding),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// Asks before leaving an editor whose field still holds a value that could
/// not be saved.
Future<bool> confirmLeave(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Leave without saving?'),
      content: const Text(
        'A field holds a value that could not be saved. Leaving drops it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  return leave == true;
}

/// Asks before a delete that cascades and has no undo.
Future<bool> confirmDelete(BuildContext context, String what) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $what?'),
      content: Text(
        'Delete $what and everything logged against it? This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
