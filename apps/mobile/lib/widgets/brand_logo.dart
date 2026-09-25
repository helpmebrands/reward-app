import 'package:flutter/material.dart';

import 'brand_lockup.dart';

/// The icon and two-line wordmark with the tagline, drawn above the message
/// on the screens reached from a link, so people see where they landed.
///
/// Like [BrandLockup], a labelled image and never a heading, the `-dark`
/// file in the dark theme, scaled down rather than cut off when narrow.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key});

  static const Size size = Size(200, 71);

  @override
  Widget build(BuildContext context) {
    final suffix = Theme.of(context).brightness == Brightness.dark
        ? '-dark'
        : '';
    return Semantics(
      label: BrandLockup.label,
      image: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Image.asset(
          'assets/logo/helpmereward-logo$suffix.png',
          width: size.width,
          height: size.height,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
