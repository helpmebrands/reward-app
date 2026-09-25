import 'package:flutter/material.dart';

import '../widgets/brand_lockup.dart';
import 'width_class.dart';

/// The one bar the four tabs share: the brand lockup on the left and the
/// Settings gear on the right, 64 high, its content aligned to the content
/// column so the logo and the gear sit on the column's margins at every
/// width class.
///
/// Page coloured with no divider at rest, the surface-container colour once
/// content scrolls under it. The lockup is a labelled image, not a heading,
/// so the bar adds no heading of its own ([AppBar.excludeHeaderSemantics]).
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAppBar({
    super.key,
    required this.widthClass,
    required this.onSettings,
  });

  static const double height = 64;

  /// The gear's touch target reaches this far past its glyph, so the glyph
  /// ends on the margin while the target overhangs it.
  static const double _gearOverhang = 12;

  /// Room between the lockup and the gear.
  static const double _breathing = 8;

  final WidthClass widthClass;
  final VoidCallback onSettings;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = theme.scaffoldBackgroundColor;
    final scrolled = theme.colorScheme.surfaceContainer;
    return AppBar(
      toolbarHeight: height,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      excludeHeaderSemantics: true,
      backgroundColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.scrolledUnder) ? scrolled : page,
      ),
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Align(
        child: ConstrainedBox(
          key: const Key('brand-app-bar'),
          constraints: BoxConstraints(maxWidth: widthClass.column),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: widthClass.padding,
              end: widthClass.padding - _gearOverhang,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(end: _breathing),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: BrandLockup(),
                    ),
                  ),
                ),
                // A label for the screen reader and a tooltip for the
                // pointer; the tooltip stays out of the semantics so the
                // name is read once.
                MergeSemantics(
                  child: Semantics(
                    label: 'Settings',
                    child: Tooltip(
                      message: 'Settings',
                      excludeFromSemantics: true,
                      child: IconButton(
                        onPressed: onSettings,
                        color: theme.colorScheme.onSurfaceVariant,
                        icon: const Icon(Icons.settings_outlined, size: 24),
                      ),
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
