import 'package:flutter/material.dart';

/// The logos mounted on screen that the cold start's hand-off can land on
/// (`LogoHandOff`), and whether they are hidden while its layers stand in
/// for them.
class LogoTargets extends ChangeNotifier {
  /// Starts [hidden] when the hand-off is about to play.
  LogoTargets(this._hidden);

  bool _hidden;

  /// While true every [LogoTarget] draws nothing but keeps its semantics.
  bool get hidden => _hidden;
  set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    notifyListeners();
  }

  final List<BuildContext> _mounted = [];

  /// The render box of the most recently mounted target that has been laid
  /// out, so one under an opaque route, never laid out, is passed over.
  RenderBox? get laidOut {
    for (final context in _mounted.reversed) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) return box;
    }
    return null;
  }
}

/// Puts [LogoTargets] in scope for the logos below.
class LogoTargetsScope extends InheritedNotifier<LogoTargets> {
  const LogoTargetsScope({
    super.key,
    required LogoTargets targets,
    required super.child,
  }) : super(notifier: targets);
}

/// A logo the hand-off can land on. It registers with the [LogoTargets] in
/// scope, and while they are hidden draws nothing but stays the one
/// "HelpMe reward" node. With none in scope it is just [child].
class LogoTarget extends StatefulWidget {
  const LogoTarget({super.key, required this.child});

  final Widget child;

  @override
  State<LogoTarget> createState() => _LogoTargetState();
}

class _LogoTargetState extends State<LogoTarget> {
  LogoTargets? _targets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targets = context
        .dependOnInheritedWidgetOfExactType<LogoTargetsScope>()
        ?.notifier;
    if (targets == _targets) return;
    _targets?._mounted.remove(context);
    _targets = targets?.._mounted.add(context);
  }

  @override
  void dispose() {
    _targets?._mounted.remove(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: _targets?.hidden == true ? 0 : 1,
    alwaysIncludeSemantics: true,
    child: widget.child,
  );
}
