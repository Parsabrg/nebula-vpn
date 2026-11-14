import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';
import 'look.dart';

/// Look, accent and "Reduce transparency", as theme_mode_controller.dart
/// does the theme mode: read once from storage, changed app-wide at once,
/// written back.
class AppearanceController extends Notifier<AppearanceChoice> {
  @override
  AppearanceChoice build() => ref.watch(appearanceStoreProvider).read();

  Future<void> setLook(NebulaLook look) => _save(state.copyWith(look: look));

  Future<void> setAccent(NebulaAccent accent) =>
      _save(state.copyWith(accent: accent));

  Future<void> setReduceTransparency({required bool enabled}) =>
      _save(state.copyWith(reduceTransparency: enabled));

  Future<void> _save(AppearanceChoice next) async {
    state = next;
    await ref.read(appearanceStoreProvider).write(next);
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppearanceChoice>(
      AppearanceController.new,
    );
