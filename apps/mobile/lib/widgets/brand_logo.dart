import 'package:flutter/material.dart';

import 'brand_lockup.dart';
import 'logo_target.dart';

/// The brand logo with its tagline, drawn in the page rather than in a bar:
/// the icon and two-line wordmark above the message on the screens reached
/// from a link, and the stacked version centred on Sign in.
///
/// Like [BrandLockup], a labelled image and never a heading, the `-dark`
/// file in the dark theme, scaled down rather than cut off when narrow.
/// The stacked one is where the cold start's logo hand-off lands on Sign
/// in ([LogoTarget]).
class BrandLogo extends StatelessWidget {
  /// The icon beside the two-line wordmark and tagline.
  const BrandLogo({super.key})
    : _name = 'helpmereward-logo',
      _size = const Size(200, 71),
      _shape = null;

  /// The icon above the wordmark and tagline.
  const BrandLogo.stacked({super.key})
    : _name = 'helpmereward-logo-vertical',
      _size = const Size(160, 170),
      _shape = LogoShape.stacked;

  final String _name;
  final Size _size;

  /// Set when the hand-off can land here.
  final LogoShape? _shape;

  @override
  Widget build(BuildContext context) {
    final suffix = Theme.of(context).brightness == Brightness.dark
        ? '-dark'
        : '';
    final logo = Semantics(
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
    final shape = _shape;
    return shape == null ? logo : LogoTarget(shape: shape, child: logo);
  }
}
