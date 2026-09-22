import 'package:flutter/widgets.dart';

/// Material's three window width classes as `design#Responsive layout`
/// fixes them for this product: the content column and the screen padding
/// each class carries. The shell computes the class once from the window
/// width and hands it down through [WidthClassScope].
enum WidthClass {
  compact(column: 402, padding: 20),
  medium(column: 560, padding: 24),
  expanded(column: 720, padding: 28);

  const WidthClass({required this.column, required this.padding});

  /// The content column's maximum width in logical pixels.
  final double column;

  /// The screen padding inside the column.
  final double padding;

  static WidthClass forWidth(double width) => width < 600
      ? compact
      : width < 1024
      ? medium
      : expanded;

  /// The class the shell computed. A screen rendered outside the shell, as
  /// in a widget test or a preview, is the phone design.
  static WidthClass of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WidthClassScope>()
          ?.widthClass ??
      compact;
}

/// Hands the shell's [WidthClass] down to the screens.
class WidthClassScope extends InheritedWidget {
  const WidthClassScope({
    super.key,
    required this.widthClass,
    required super.child,
  });

  final WidthClass widthClass;

  @override
  bool updateShouldNotify(WidthClassScope oldWidget) =>
      oldWidget.widthClass != widthClass;
}
