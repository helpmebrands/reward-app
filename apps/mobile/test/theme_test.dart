import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/main.dart';
import 'package:reward/theme/nocturne_tokens.dart';
import 'package:reward/theme/theme.dart';

void main() {
  // @lat: [[mobile-tests#Theme#Both themes carry the Nocturne token colours]]
  testWidgets('the dark and light themes carry the token colours', (
    tester,
  ) async {
    final dark = nocturneTheme(Brightness.dark);
    expect(dark.colorScheme.primary, const Color(0xFF9184D9));
    expect(dark.colorScheme.surface, const Color(0xFF232532));
    expect(dark.colorScheme.onSurface, const Color(0xFFE9E9ED));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF161826));
    expect(dark.extension<NocturneTokens>(), same(NocturneTokens.dark));

    final light = nocturneTheme(Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF5D5294));
    expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(light.colorScheme.onSurface, const Color(0xFF232532));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF3F5FE));
    expect(light.extension<NocturneTokens>(), same(NocturneTokens.light));
  });

  // @lat: [[mobile-tests#Theme#The app follows the platform brightness]]
  testWidgets('the app picks the theme from the platform brightness', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = AppStore(
      store: MemorySnapshotStore(),
      clock: () => '2026-09-16',
    );
    await store.load();
    await tester.pumpWidget(RewardApp(store: store));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Start with one card'));
    expect(Theme.of(context).colorScheme.primary, NocturneTokens.dark.accent);
    expect(
      Theme.of(context).extension<NocturneTokens>()!.soon.ground,
      const Color(0xFF2B2741),
    );
  });
}
