import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// How far the row travels to fully expose one action; a side with two
/// parks at twice this.
const double swipeActionWidth = 84;

/// Horizontal movement needed before the gesture counts as a swipe.
const double _directionLock = 10;

/// Past this fraction of the action width, releasing parks the row open.
const double _commitRatio = 0.55;

/// Logical pixels per millisecond past which a short flick still commits.
const double _flickVelocity = 0.45;

/// `accent` for the constructive action, `quiet` for a reversible one,
/// `away` for one that takes the credit off the list.
enum SwipeTone { accent, quiet, locked, away }

class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onAct,
  });

  final String label;
  final IconData icon;
  final SwipeTone tone;
  final VoidCallback onAct;
}

/// A row with swipe actions: the PWA's `SwipeRow`.
///
/// Material's `Dismissible` fires on release and cannot park, so this is a
/// gesture of its own with the behaviours that make a swipe usable on a
/// phone: the gesture only becomes a swipe once horizontal movement clearly
/// beats vertical, so a flick down the list never half-opens a row; the row
/// rubber-bands past the action width; a quick flick commits even when it is
/// short; and releasing past the threshold parks the row open with the
/// button exposed rather than firing, because an irreversible action should
/// not be one accidental flick away. A tap anywhere else closes an open row.
/// The mouse is ignored on purpose, as in the PWA. Every action is also
/// reachable without the gesture, so swipe is an accelerator, never the only
/// route.
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.child,
    this.leading,
    this.trailing = const [],
    this.disabled = false,
  });

  final Widget child;

  /// Revealed by swiping right (the row moves right).
  final SwipeAction? leading;

  /// Revealed by swiping left (the row moves left), side by side in this
  /// order.
  final List<SwipeAction> trailing;

  /// Disables the gesture, for rows with nothing to act on.
  final bool disabled;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// How far the side [delta] points at opens: one action width per
  /// action, or zero when it has none.
  double _width(double delta) => delta > 0
      ? (widget.leading == null ? 0 : swipeActionWidth)
      : swipeActionWidth * widget.trailing.length;

  bool _available(double delta) => _width(delta) > 0;

  /// Resistance past the actions' width, so the row never feels unbounded.
  double _rubberBand(double delta) {
    final width = _width(delta);
    if (delta.abs() <= width) return delta;
    final excess = delta.abs() - width;
    return delta.sign * (width + excess * 0.28);
  }

  void _animateTo(double target) {
    final from = _offset;
    if (from == target) return;
    final curve = CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic);
    void tick() =>
        setState(() => _offset = from + (target - from) * curve.value);
    curve.addListener(tick);
    _settle.forward(from: 0).whenCompleteOrCancel(() {
      curve.removeListener(tick);
      curve.dispose();
    });
  }

  void _close() {
    if (_offset != 0) _animateTo(0);
  }

  void _onStart() => _settle.stop();

  void _onUpdate(double travel) {
    setState(() => _offset = _available(travel) ? _rubberBand(travel) : 0);
  }

  void _onEnd(double velocity) {
    final travelled = _offset;
    final flicked =
        velocity.abs() > _flickVelocity && velocity.sign == travelled.sign;
    final width = _width(travelled);
    final committed = travelled.abs() > width * _commitRatio || flicked;
    // Park open rather than firing: an action a flick away should still need
    // a deliberate tap.
    _animateTo(committed && width > 0 ? travelled.sign * width : 0);
  }

  void _act(SwipeAction action) {
    action.onAct();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final open = _offset != 0;
    final leading = widget.leading;
    final actions = _offset > 0 ? [?leading] : widget.trailing;
    final content = Transform.translate(
      offset: Offset(_offset, 0),
      child: KeyedSubtree(key: const Key('swipe-content'), child: widget.child),
    );
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      gestures: widget.disabled
          ? const {}
          : {
              _SwipeRecognizer:
                  GestureRecognizerFactoryWithHandlers<_SwipeRecognizer>(
                    _SwipeRecognizer.new,
                    (recognizer) => recognizer
                      ..onStart = _onStart
                      ..onUpdate = _onUpdate
                      ..onEnd = _onEnd,
                  ),
            },
      child: TapRegion(
        onTapOutside: (_) => _close(),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
          child: Stack(
            children: [
              // The actions sit behind the content, which slides over them. A
              // closed row keeps them out of the tree and the semantics.
              if (open && actions.isNotEmpty)
                Positioned.fill(
                  child: Align(
                    alignment: _offset > 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action in actions)
                          _ActionButton(
                            action: action,
                            width:
                                math.max(_offset.abs(), _width(_offset)) /
                                actions.length,
                            align: _offset > 0
                                ? CrossAxisAlignment.start
                                : actions.length > 1
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.end,
                            onPressed: () => _act(action),
                          ),
                      ],
                    ),
                  ),
                ),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.width,
    required this.align,
    required this.onPressed,
  });

  final SwipeAction action;
  final double width;

  /// Toward the row's edge for a lone action, centred for a pair.
  final CrossAxisAlignment align;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final (background, foreground) = switch (action.tone) {
      SwipeTone.accent => (tokens.accentRamp[800]!, tokens.accentRamp[100]!),
      SwipeTone.quiet => (tokens.neutral[900]!, tokens.neutral[300]!),
      SwipeTone.locked => (tokens.locked.ground, tokens.locked.foreground),
      SwipeTone.away => (tokens.neutral[800]!, tokens.neutral[100]!),
    };
    return SizedBox(
      width: width,
      height: double.infinity,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.only(
              left: align == CrossAxisAlignment.start ? Space.s6 : Space.s3,
              right: align == CrossAxisAlignment.end ? Space.s6 : Space.s3,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: align,
              children: [
                Icon(action.icon, size: 18, color: foreground),
                const SizedBox(height: Space.s1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    action.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The swipe gesture: direction-locked at [_directionLock] with the vertical
/// axis winning ties, so the list's own scroll is never stolen, and reporting
/// the travel past the lock and the release velocity.
class _SwipeRecognizer extends OneSequenceGestureRecognizer {
  _SwipeRecognizer() : super(supportedDevices: _touchAndPen);

  static const Set<PointerDeviceKind> _touchAndPen = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  VoidCallback? onStart;
  ValueChanged<double>? onUpdate;

  /// Velocity in logical pixels per millisecond, signed like the travel.
  ValueChanged<double>? onEnd;

  Offset? _start;
  VelocityTracker? _tracker;
  bool _accepted = false;

  @override
  String get debugDescription => 'swipe';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _start = event.position;
    _tracker = VelocityTracker.withKind(event.kind);
    _accepted = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    final start = _start;
    if (start == null) return;
    if (event is PointerMoveEvent) {
      _tracker!.addPosition(event.timeStamp, event.position);
      final delta = event.position - start;
      if (!_accepted) {
        if (delta.dy.abs() > _directionLock &&
            delta.dy.abs() > delta.dx.abs()) {
          // A vertical scroll: bow out entirely and let the list take it.
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          return;
        }
        if (delta.dx.abs() < _directionLock) return;
        _accepted = true;
        resolve(GestureDisposition.accepted);
        onStart?.call();
      }
      // Subtract the lock distance so the row starts moving from the finger.
      onUpdate?.call(delta.dx - delta.dx.sign * _directionLock);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_accepted) {
        final velocity = event is PointerUpEvent
            ? _tracker!.getVelocity().pixelsPerSecond.dx / 1000
            : 0.0;
        onEnd?.call(velocity);
      } else {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _start = null;
    _tracker = null;
    _accepted = false;
  }
}
