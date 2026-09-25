import 'package:flutter/material.dart';

import 'brand_lockup.dart';

/// The brand logo with its tagline, drawn in the page rather than in a bar:
/// the icon and two-line wordmark above the message on the screens reached
/// from a link, and the stacked version centred on Welcome and Sign in.
///
/// Like [BrandLockup], a labelled image and never a heading, the `-dark`
/// file in the dark theme, scaled down rather than cut off when narrow.
class BrandLogo extends StatelessWidget {
  /// The icon beside the two-line wordmark and tagline.
  const BrandLogo({super.key})
    : _name = 'helpmereward-logo',
      _size = const Size(200, 71);

  /// The icon above the wordmark and tagline.
  const BrandLogo.stacked({super.key})
    : _name = 'helpmereward-logo-vertical',
      _size = const Size(160, 170);

  final String _name;
  final Size _size;

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
          'assets/logo/$_name$suffix.png',
          width: _size.width,
          height: _size.height,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
