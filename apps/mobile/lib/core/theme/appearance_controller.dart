import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/storage_providers.dart';
import 'look.dart';

/// Look, accent and "Reduce transparency", as theme_mode_controller.dart
/// does the theme mode: read once from storage, changed app-wide at once,
/// written back.
class AppearanceController extends Notifier<AppearanceChoice> {
  /// "on" while Reduce transparency is on because the device drew Liquid
  /// glass too slowly (glass_performance_guard.dart); "declined" once it was
  /// turned off again, after which the app never turns it on by itself.
  static const String automaticSolidKey = 'nebula.solid_auto';

  @override
  AppearanceChoice build() => ref.watch(appearanceStoreProvider).read();

  Future<void> setLook(NebulaLook look) => _save(state.copyWith(look: look));

  Future<void> setAccent(NebulaAccent accent) =>
      _save(state.copyWith(accent: accent));

  Future<void> setReduceTransparency({required bool enabled}) async {
    final SharedPreferences preferences = ref.read(sharedPreferencesProvider);
    if (!enabled && preferences.getString(automaticSolidKey) == 'on') {
      await preferences.setString(automaticSolidKey, 'declined');
    }
    await _save(state.copyWith(reduceTransparency: enabled));
  }

  /// Solid panels because this device cannot draw see-through ones smoothly.
  Future<void> fallBackToSolidPanels() async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(automaticSolidKey, 'on');
    await _save(state.copyWith(reduceTransparency: true));
  }

  Future<void> _save(AppearanceChoice next) async {
    state = next;
    await ref.read(appearanceStoreProvider).write(next);
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppearanceChoice>(
      AppearanceController.new,
    );

/// Whether Reduce transparency is on because the app turned it on.
final solidPanelsAutomaticProvider = Provider<bool>((Ref ref) {
  final AppearanceChoice choice = ref.watch(appearanceProvider);
  return choice.reduceTransparency &&
      ref
              .watch(sharedPreferencesProvider)
              .getString(AppearanceController.automaticSolidKey) ==
          'on';
});
