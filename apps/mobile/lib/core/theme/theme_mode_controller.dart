import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../storage/storage_providers.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return ref.watch(themePreferenceStoreProvider).read();
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(themePreferenceStoreProvider).write(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
