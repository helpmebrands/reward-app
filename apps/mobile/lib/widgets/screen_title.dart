import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/ui_state.dart';
import '../shell/ui_scope.dart';

/// A screen's one heading: the PWA's `h1` and `useScreenTitle` in one.
///
/// It is the level-one heading a screen reader lands on, it sets the window
/// title to "Screen · HelpMe Reward" (WCAG 2.4.2), and it carries a focus
/// node registered under the screen's location so the app can move focus
/// here on navigation (WCAG 2.4.3). Section titles are level two.
class ScreenTitle extends StatefulWidget {
  const ScreenTitle({
    super.key,
    required this.label,
    this.text,
    this.windowTitle,
    this.style,
  });

  /// What the heading says to a screen reader, and the window title unless
  /// [windowTitle] differs.
  final String label;

  /// What is drawn; the label when null.
  final String? text;
  final String? windowTitle;
  final TextStyle? style;

  @override
  State<ScreenTitle> createState() => ScreenTitleState();
}

class ScreenTitleState extends State<ScreenTitle> {
  final FocusNode focusNode = FocusNode(
    debugLabel: 'screen title',
    skipTraversal: true,
  );
  UiState? _ui;
  String? _location;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registered under the location being shown when the screen mounts,
    // which is this screen's own: a branch registers on its first visit and
    // a full-screen route on every push.
    final ui = UiScope.maybeOf(context);
    final router = GoRouter.maybeOf(context);
    if (ui == null || router == null) return;
    final location = router.routerDelegate.currentConfiguration.uri.path;
    if (_ui != ui || _location != location) {
      _ui?.headings.remove(_location);
      _ui = ui;
      _location = location;
      ui.headings[location] = focusNode;
    }
    if (ui.pendingHeadingFocus == location) {
      ui.pendingHeadingFocus = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    if (_ui?.headings[_location] == focusNode) _ui?.headings.remove(_location);
    focusNode.removeListener(_focusChanged);
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Title(
      title: '${widget.windowTitle ?? widget.label} · HelpMe Reward',
      color: theme.colorScheme.primary,
      // The focus widget adds no node of its own; the heading node carries
      // the focus flags, so a screen reader lands on one thing.
      child: Focus(
        focusNode: focusNode,
        includeSemantics: false,
        descendantsAreFocusable: false,
        child: Semantics(
          container: true,
          header: true,
          headingLevel: 1,
          label: widget.label,
          focusable: true,
          focused: focusNode.hasFocus,
          excludeSemantics: true,
          child: Text(widget.text ?? widget.label, style: widget.style),
        ),
      ),
    );
  }
}
