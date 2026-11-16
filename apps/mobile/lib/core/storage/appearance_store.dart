import 'package:shared_preferences/shared_preferences.dart';

import '../theme/look.dart';

/// Persists the look, accent and "Reduce transparency" chosen in Settings,
/// Appearance. Not sensitive: plain local storage, as the theme mode is
/// (theme_preference_store.dart).
abstract interface class AppearanceStore {
  AppearanceChoice read();
  Future<void> write(AppearanceChoice choice);
}

class SharedPreferencesAppearanceStore implements AppearanceStore {
  SharedPreferencesAppearanceStore(this._preferences);

  static const String _look = 'nebula.look';
  static const String _accent = 'nebula.accent';
  static const String _solid = 'nebula.reduce_transparency';

  final SharedPreferences _preferences;

  @override
  AppearanceChoice read() => AppearanceChoice(
    look: NebulaLook.parse(_preferences.getString(_look)),
    accent: NebulaAccent.parse(_preferences.getString(_accent)),
    reduceTransparency: _preferences.getBool(_solid) ?? false,
  );

  @override
  Future<void> write(AppearanceChoice choice) async {
    await _preferences.setString(_look, choice.look.name);
    await _preferences.setString(_accent, choice.accent.name);
    await _preferences.setBool(_solid, choice.reduceTransparency);
  }
}

/// In-memory fake for tests.
class InMemoryAppearanceStore implements AppearanceStore {
  AppearanceChoice _choice = AppearanceChoice.defaults;

  @override
  AppearanceChoice read() => _choice;

  @override
  Future<void> write(AppearanceChoice choice) async {
    _choice = choice;
  }
}
