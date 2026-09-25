import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// What a [Field] hands its control: the focus node it watches for blur and
/// the decoration carrying the label, the hint and the invalid state.
class FieldControl {
  const FieldControl({
    required this.focusNode,
    required this.decoration,
    required this.visibleError,
  });

  final FocusNode focusNode;
  final InputDecoration decoration;

  /// The error on show, or null.
  final String? visibleError;
}

/// A labelled control with a hint and an error slot (WCAG 3.3.1, 3.3.2): the
/// PWA's `Field`.
///
/// The field owns *when* an error shows: after the control has been left
/// once, or once the form has been submitted, never on the first keystroke.
/// The parent owns *whether* there is one, as a pure rule from the domain's
/// validation. The control is built by the caller so any widget can sit
/// here; it is handed the focus node and the decoration to use. The error
/// slot is always present and a live region, so a message arriving in it is
/// announced; a required field carries a `*` the form explains once.
class Field extends StatefulWidget {
  const Field({
    super.key,
    required this.label,
    this.hint,
    this.error,
    this.required = false,
    this.submitted = false,
    required this.focusNode,
    required this.builder,
  });

  final String label;
  final String? hint;

  /// The current rule result for the value.
  final String? error;
  final bool required;

  /// True once the form has been submitted; forces errors into view.
  final bool submitted;

  /// Owned by the form, so it can focus the first invalid field on submit.
  final FocusNode focusNode;
  final Widget Function(BuildContext context, FieldControl control) builder;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(Field old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (!widget.focusNode.hasFocus && !_touched) {
      setState(() => _touched = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final visible = (_touched || widget.submitted) ? widget.error : null;
    final control = FieldControl(
      focusNode: widget.focusNode,
      decoration: InputDecoration(
        labelText: widget.required ? '${widget.label} *' : widget.label,
        // The red border without the decorator's own message: the hint and
        // the message live in the slots below, where the decorator would
        // hide the hint behind the error and where the error is always
        // announced.
        error: visible == null ? null : const SizedBox.shrink(),
      ),
      visibleError: visible,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.builder(context, control),
        if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: Text(
              widget.hint!,
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          ),
        MergeSemantics(
          child: Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.s1),
              child: Text(
                visible ?? '',
                style: text.bodySmall?.copyWith(
                  color: tokens.missed.foreground,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
