import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';

/// A modal sheet in the shape the width calls for, drawn over [child].
///
/// On a phone it is Material's bottom sheet on Nocturne's surfaces: a drag
/// handle that dismisses, a scrim that closes on tap. At medium it is a
/// centred dialog at most 480 wide, and at expanded a panel docked on the
/// trailing edge, 380 wide and full height, with no scrim so the list beside
/// it stays usable. All three scope a named route for the screen reader,
/// take focus on open and hand it back on close, close on Escape and on the
/// system back, and keep keyboard traversal inside.
class SheetHost extends StatefulWidget {
  const SheetHost({
    super.key,
    required this.open,
    required this.title,
    required this.onClose,
    required this.sheet,
    required this.child,
    this.widthClass = WidthClass.compact,
  });

  final bool open;

  /// Announced as the route's name.
  final String title;
  final VoidCallback onClose;

  /// The sheet's content; ignored while closed.
  final Widget? sheet;

  /// The screen beneath.
  final Widget child;
  final WidthClass widthClass;

  @override
  State<SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<SheetHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'sheet');
  FocusNode? _returnTo;

  @override
  void initState() {
    super.initState();
    _slide = BottomSheet.createAnimationController(this);
    if (widget.open) _opened();
  }

  @override
  void didUpdateWidget(SheetHost old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) _opened();
    if (!widget.open && old.open) _closed();
  }

  /// Remember where focus was so it can go back there, move focus into the
  /// sheet once it is built, and slide in. Autofocus alone is not enough: the
  /// framework honours it only when nothing on the screen behind has focus.
  void _opened() {
    _returnTo = FocusManager.instance.primaryFocus;
    _slide.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.open) _scope.requestFocus();
    });
  }

  void _closed() {
    final node = _returnTo;
    _returnTo = null;
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.canRequestFocus) node.requestFocus();
    });
  }

  @override
  void dispose() {
    _slide.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = PopScope(
      canPop: !widget.open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: widget.child,
    );
    if (!widget.open) return shell;

    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final size = MediaQuery.sizeOf(context);
    // The shortcuts sit above the scope so Escape is handled whether the
    // scope itself or a control inside it holds focus.
    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: FocusScope(node: _scope, child: widget.sheet!),
    );

    // The route semantics wrap the whole presentation, drag handle included,
    // and carry the key the tests measure.
    Widget route(Widget presentation) => Semantics(
      key: const Key('credit-sheet'),
      scopesRoute: true,
      namesRoute: true,
      label: widget.title,
      explicitChildNodes: true,
      child: presentation,
    );

    return switch (widget.widthClass) {
      WidthClass.compact => Stack(
        fit: StackFit.expand,
        children: [
          shell,
          _scrim(),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _slide,
              builder: (context, child) => ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: _slide.value,
                  child: child,
                ),
              ),
              child: route(
                BottomSheet(
                  animationController: _slide,
                  showDragHandle: true,
                  backgroundColor: tokens.surfaceRaised,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(Radii.lg),
                    ),
                  ),
                  constraints: BoxConstraints(maxHeight: size.height * 0.92),
                  onClosing: widget.onClose,
                  builder: (context) => body,
                ),
              ),
            ),
          ),
        ],
      ),
      WidthClass.medium => Stack(
        fit: StackFit.expand,
        children: [
          shell,
          _scrim(),
          Center(
            child: Dialog(
              backgroundColor: tokens.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(Radii.lg)),
                side: BorderSide(color: tokens.surfaceLine),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: size.height * 0.85,
                ),
                child: route(body),
              ),
            ),
          ),
        ],
      ),
      WidthClass.expanded => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: shell),
          route(
            Material(
              color: tokens.surfaceRaised,
              child: Container(
                width: 380,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: tokens.surfaceLine)),
                ),
                child: body,
              ),
            ),
          ),
        ],
      ),
    };
  }

  Widget _scrim() => ModalBarrier(
    key: const Key('sheet-scrim'),
    color: Colors.black54,
    dismissible: true,
    onDismiss: widget.onClose,
    semanticsLabel: 'Close ${widget.title}',
  );
}
