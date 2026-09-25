import 'package:flutter/material.dart';

/// The brand in the app bar: the icon and one-line wordmark (the lockup)
/// when the width it is given fits it, otherwise the wordmark alone, scaled
/// down rather than cut off when even that does not fit.
///
/// Artwork at a fixed size, so it does not follow the system text scale. It
/// is a labelled image, not a heading: each screen keeps its one level-one
/// `ScreenTitle`. The dark theme draws the files with light-grey text.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  static const String label = 'HelpMe reward';
  static const Size lockupSize = Size(224, 32);
  static const Size wordmarkSize = Size(154, 22);

  @override
  Widget build(BuildContext context) {
    final suffix = Theme.of(context).brightness == Brightness.dark
        ? '-dark'
        : '';
    return LayoutBuilder(
      builder: (context, constraints) {
        final lockup = constraints.maxWidth >= lockupSize.width;
        final size = lockup ? lockupSize : wordmarkSize;
        final name = lockup
            ? 'helpmereward-logo-horz-sanstag'
            : 'helpmereward-logotype-horz';
        return Semantics(
          label: label,
          image: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Image.asset(
              'assets/logo/$name$suffix.png',
              width: size.width,
              height: size.height,
              excludeFromSemantics: true,
            ),
          ),
        );
      },
    );
  }
}
