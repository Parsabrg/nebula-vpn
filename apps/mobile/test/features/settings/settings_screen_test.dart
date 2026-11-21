import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nebula_mobile/core/storage/storage_providers.dart';
import 'package:nebula_mobile/core/theme/appearance_controller.dart';
import 'package:nebula_mobile/core/theme/look.dart';
import 'package:nebula_mobile/core/theme/theme_mode_controller.dart';
import 'package:nebula_mobile/features/settings/appearance_screen.dart';
import 'package:nebula_mobile/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/localised_app.dart';

Future<ProviderContainer> _containerWithPreferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(preferences),
    ],
  );
}

void main() {
  testWidgets('selecting a theme mode updates and persists state', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _containerWithPreferences();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localisedApp(const AppearanceScreen()),
      ),
    );

    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.scrollUntilVisible(find.text('Dark'), 200);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('the theme control is reachable by its semantics label', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _containerWithPreferences();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localisedApp(const AppearanceScreen()),
      ),
    );

    await tester.scrollUntilVisible(find.text('Dark'), 200);
    expect(find.bySemanticsLabel('Theme mode'), findsOneWidget);
  });

  testWidgets('Settings opens Appearance, which says the look and mode', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _containerWithPreferences();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localisedApp(const SettingsScreen()),
      ),
    );

    expect(find.text('Minimal · System'), findsOneWidget);
  });

  testWidgets('a look, an accent and Reduce transparency persist at once', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _containerWithPreferences();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localisedApp(const AppearanceScreen()),
      ),
    );

    // Reduce transparency is offered on Liquid glass only.
    expect(find.text('Reduce transparency'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Liquid glass'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).look, NebulaLook.glass);
    await tester.scrollUntilVisible(find.text('Reduce transparency'), 200);
    await tester.tap(find.text('Reduce transparency'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.bySemanticsLabel('Teal'), 200);
    await tester.tap(find.bySemanticsLabel('Teal'));
    await tester.pumpAndSettle();

    final AppearanceChoice now = container.read(appearanceProvider);
    expect(now.reduceTransparency, isTrue);
    expect(now.accent, NebulaAccent.teal);
    // Written through to storage, so the next launch starts with them.
    final SharedPreferences stored = await SharedPreferences.getInstance();
    expect(stored.getString('nebula.look'), 'glass');
    expect(stored.getString('nebula.accent'), 'teal');
    expect(stored.getBool('nebula.reduce_transparency'), isTrue);
  });
}
